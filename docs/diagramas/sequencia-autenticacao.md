# Autenticação e autorização

Como um operador obtém um token e como esse token é aceito nas rotas
protegidas. São dois fluxos que se encontram no mesmo segredo: a Lambda
**emite** o JWT, o monolito **valida**. Nenhum dos dois chama o outro.

O racional e as alternativas descartadas estão na [RFC-0003](../rfc/0003-estrategia-de-autenticacao.md) e na
[ADR-0009](../adr/0009-jwt-hs256-com-segredo-compartilhado.md), que também fixa a ordem exata da validação e o caminho
do segredo.

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
        Note right of L: mesma resposta de senha errada:<br/>não revela quais usuários existem
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

Três detalhes que não aparecem no diagrama:

- **O segredo e o pool são resolvidos no init do container, não por
  invocação.** Um container quente reaproveita os dois, o que evita uma chamada
  ao Secrets Manager e uma abertura de conexão por requisição.
- **`MaxConns` do pool é baixo de propósito.** Cada container quente mantém o
  próprio pool, e o teto real é o `max_connections` do RDS, compartilhado com
  até 10 pods da API ([ADR-0004](../adr/0004-hpa-no-deployment-da-api.md)).
- **Os parâmetros de custo do argon2id vêm do hash gravado**, e não de
  configuração: aumentar o custo passa a valer para senhas novas, sem
  invalidar as antigas.

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
    Note over GW: não casa com /auth/*,<br/>cai na rota $default
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

## Papéis e rotas públicas

| Papel | Alcance |
|---|---|
| `admin` | tudo, incluindo `/users` (manutenção de operadores) |
| `employee` | clientes, veículos, catálogos, OS e itens de OS |

`/users` é a única família de rotas restrita a `admin`. Papel ausente ou vazio
no token é tratado como token inválido, e não como ausência de papel.

Estas rotas não exigem `Authorization`:

| Rota | Por que é pública |
|---|---|
| `/ping`, `/ready` | healthcheck, usado pelas probes e pelo monitor externo |
| `/docs/*` | contrato OpenAPI da API |
| `GET /public/work-orders/:code?document=...` | consulta de status pelo cliente final |
| `/public/approvals/*` | aprovação e reprovação de serviços pelo cliente final |

As duas últimas são o canal do cliente final, e a prova de posse é o
identificador não adivinhável (UUID v4 da OS ou do serviço) somado ao documento
do cliente. A discussão de risco desse canal está na
[RFC-0003](../rfc/0003-estrategia-de-autenticacao.md).

**O monolito não conhece a Lambda.** Ele valida assinatura, expiração e a
presença das claims `user` e `role`. Se a Lambda for substituída por outro
emissor que assine com o mesmo segredo, nada muda no monolito. Um teste de
contrato em cada repositório, com token *golden* fixo em
`testdata/token.golden`, garante que os dois lados não divirjam sem que o CI
perceba.
