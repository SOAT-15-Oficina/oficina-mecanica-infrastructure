# Diagrama de sequência — autenticação

Como um operador obtém um token e como esse token é aceito nas rotas
protegidas. São dois fluxos que se encontram no mesmo segredo: a Lambda
**emite** o JWT, o monolito **valida**. Nenhum dos dois chama o outro.

## 1. Login e emissão do token

```mermaid
sequenceDiagram
    autonumber
    actor OP as Operador
    participant CF as CloudFront
    participant GW as API Gateway
    participant L as Lambda auth
    participant SM as Secrets Manager
    participant DB as RDS PostgreSQL

    Note over L,SM: init do container (uma vez, não por invocação)
    L->>SM: GetSecretValue (JWT + credencial do RDS)
    SM-->>L: segredos
    L->>DB: abre pool (MaxConns baixo por container)

    OP->>CF: POST /api/auth/login<br/>{username, password}
    CF->>CF: Function remove o prefixo /api
    CF->>GW: POST /auth/login
    GW->>L: evento APIGatewayV2HTTPRequest<br/>routeKey "POST /auth/login"

    L->>DB: SELECT * FROM users WHERE username = $1
    alt usuário não existe
        DB-->>L: pgx.ErrNoRows
        L-->>GW: 401 {"error":"invalid credentials"}
        Note right of L: mesma resposta de senha errada —<br/>não revela quais usuários existem
    else usuário existe
        DB-->>L: user{password_hash, role}
        L->>L: argon2id: recalcula o hash com os<br/>parâmetros gravados no próprio hash
        alt hash não confere
            L-->>GW: 401 {"error":"invalid credentials"}
        else hash confere
            L->>L: assina JWT HS256<br/>claims: user, role, iat, exp (+24h)
            L-->>GW: 200 {"token":"eyJ..."}
        end
    end
    GW-->>CF: resposta
    CF-->>OP: resposta
    Note over GW: access log JSON no CloudWatch<br/>requestId, rota, status, latência
```

## 2. Consumo de uma rota protegida

```mermaid
sequenceDiagram
    autonumber
    actor OP as Operador
    participant CF as CloudFront
    participant GW as API Gateway
    participant VL as VPC Link
    participant ALB as ALB interno
    participant API as Pod da API (monolito)
    participant DB as RDS PostgreSQL

    OP->>CF: GET /api/work-orders<br/>Authorization: Bearer eyJ...
    CF->>GW: GET /work-orders
    Note over GW: não casa com /auth/* →<br/>cai na rota $default
    GW->>VL: integração HTTP_PROXY
    VL->>ALB: encaminha para o listener
    ALB->>API: GET /work-orders

    API->>API: middleware Auth:<br/>parse do header, ParseToken(HS256)
    alt token ausente, malformado ou expirado
        API-->>ALB: 401 {"error":"invalid token"}
    else token válido
        API->>API: middleware RequireRoles(admin, employee)
        alt role não autorizada
            API-->>ALB: 403 {"error":"insufficient permissions"}
        else role autorizada
            API->>DB: consulta
            DB-->>API: linhas
            API-->>ALB: 200 [...]
        end
    end
    ALB-->>VL: resposta
    VL-->>GW: resposta
    GW-->>CF: resposta
    CF-->>OP: resposta
```

## Notas

- **O monolito não conhece a Lambda.** Ele valida assinatura, expiração e a
  presença das claims `user` e `role`. Se a Lambda for substituída por outro
  emissor que assine com o mesmo segredo, nada muda no monolito. Ver
  [ADR-0009](../adr/0009-jwt-hs256-com-segredo-compartilhado.md).
- **Rotas públicas por desenho**, sem `Authorization`: `/ping`, `/ready`,
  `/docs/*`, `GET /public/work-orders/:code?document=...` e
  `/public/approvals/*`. As duas últimas são o canal do cliente final e usam
  identificadores não adivinháveis (UUID da OS ou do serviço) somados ao
  documento do cliente — ver a discussão de risco na
  [RFC-0003](../rfc/0003-estrategia-de-autenticacao.md).
- **O segredo JWT nunca aparece em código nem em variável de repositório.** Vive
  no Secrets Manager; a Lambda lê no init do container, e o pod recebe via
  `Secret` do Kubernetes criado pelo Terraform.
