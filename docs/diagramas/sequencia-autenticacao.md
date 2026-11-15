# Autenticação e autorização

Como um operador obtém um token e como esse token é aceito nas rotas
protegidas. São dois fluxos que se encontram no mesmo segredo: a Lambda
**emite** o JWT, os três serviços **validam**. Na Fase 4 a Lambda não tem banco:
para conferir a senha ela chama o OS Service, dono da tabela `users`, pelo ALB
interno ([RFC-0006, seção 8](../rfc/0006-microsservicos-e-saga.md#8-a-lambda-de-autenticação)).

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
    participant ALB as ALB interno
    participant OS as OS Service

    Note over L,SM: init do container (uma vez, não por invocação)
    L->>SM: GetSecretValue (JWT + token de serviço)
    SM-->>L: segredos

    OP->>CF: POST /api/auth/login<br/>{username, password}
    CF->>CF: Function remove o prefixo /api
    CF->>GW: POST /auth/login
    GW->>L: evento APIGatewayV2HTTPRequest<br/>routeKey "POST /auth/login"

    L->>ALB: POST /internal/credentials/verify<br/>X-Service-Token, X-Request-Id
    ALB->>OS: regra /*
    OS->>OS: confere o token em tempo constante<br/>e a senha (argon2id) na tabela users
    alt usuário não existe ou senha errada
        OS-->>L: 401
        L-->>GW: 401 {"error":"invalid credentials"}
        Note right of L: mesma resposta para os dois casos:<br/>não revela quais usuários existem
    else credencial válida
        OS-->>L: 200 {id, username, role}
        L->>L: assina JWT HS256<br/>claims: user, role, iat, exp (+24h)
        L-->>GW: 200 {"token":"eyJ..."}
    else OS fora do ar, 5xx ou timeout
        L-->>GW: 500 {"error":"internal server error"}
    end
    GW-->>CF: resposta
    CF-->>OP: resposta
```

O cadastro (`POST /auth/register`) segue o mesmo caminho para
`POST /internal/users`: 201, 409 (usuário já existe) e 400 (mensagem do OS) são
repassados ao painel.

Três detalhes que não aparecem no diagrama:

- **Os segredos são resolvidos no init do container, não por invocação.** Um
  container quente não chama o Secrets Manager de novo.
- **O token de serviço é distinto do segredo do JWT.** Os dois vivem na camada
  persistente (`oficina-mecanica/<ambiente>/internal-service-token` e
  `oficina-mecanica-<ambiente>/jwt-secret`), e vazar um não dá o outro.
- **Falha do OS Service vira 500, nunca 401.** Credencial recusada e serviço
  fora do ar continuam distinguíveis no painel e nos alertas.

## 2. Consumo de uma rota protegida

```mermaid
sequenceDiagram
    autonumber
    actor OP as Operador
    participant CF as CloudFront
    participant GW as API Gateway
    participant VL as VPC Link
    participant ALB as ALB interno
    participant API as Pod do serviço (OS, Billing ou Execution)
    participant DB as Banco do serviço

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
| `/swagger`, `/docs/*` (e os equivalentes sob `/billing` e `/execution`) | contrato OpenAPI de cada serviço |
| `GET /public/work-orders/:code?document=...` (OS) | consulta de status, histórico e link de pagamento pelo cliente final |
| `/billing/public/quotes/*` (Billing) | aprovação e reprovação do orçamento pelo cliente final |
| `POST /billing/webhooks/mercadopago` (Billing) | notificação do Mercado Pago, validada pela assinatura `x-signature` |
| `POST /internal/*` (OS) | só para a Lambda; exige `X-Service-Token` |

As duas últimas são o canal do cliente final, e a prova de posse é o
identificador não adivinhável (UUID v4 da OS ou do serviço) somado ao documento
do cliente. A discussão de risco desse canal está na
[RFC-0003](../rfc/0003-estrategia-de-autenticacao.md).

**Os serviços não conhecem a Lambda.** Eles validam assinatura, expiração e a
presença das claims `user` e `role`. Se a Lambda for substituída por outro
emissor que assine com o mesmo segredo, nada muda nos serviços. Um teste de
contrato em cada repositório, com token *golden* fixo em
`testdata/token.golden`, garante que os dois lados não divirjam sem que o CI
perceba.
