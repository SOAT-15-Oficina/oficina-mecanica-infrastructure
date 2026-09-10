# Diagrama de sequência — ordem de serviço

O ciclo de vida completo: abertura, diagnóstico, orçamento por e-mail, decisão
do cliente e execução. Dois atores humanos com canais distintos — o operador
usa rotas autenticadas por JWT, o cliente usa links públicos recebidos por
e-mail.

## Máquina de estados

A transição é validada no serviço de domínio; qualquer salto fora deste mapa é
rejeitado com `ErrInvalidStatusTransition`.

```mermaid
stateDiagram-v2
    [*] --> RECEBIDA
    RECEBIDA --> EM_DIAGNOSTICO
    RECEBIDA --> CANCELADA
    EM_DIAGNOSTICO --> AGUARDANDO_APROVACAO
    EM_DIAGNOSTICO --> CANCELADA
    AGUARDANDO_APROVACAO --> APROVADO: ao menos 1 serviço aprovado
    AGUARDANDO_APROVACAO --> CANCELADA: todos reprovados
    APROVADO --> EM_EXECUCAO
    EM_EXECUCAO --> FINALIZADA
    FINALIZADA --> ENTREGUE
    ENTREGUE --> [*]
    CANCELADA --> [*]
```

Itens só podem ser adicionados ou removidos em `RECEBIDA`, `EM_DIAGNOSTICO` ou
`AGUARDANDO_APROVACAO`. Depois de aprovada, a composição da OS está congelada.

## 1. Abertura e envio do orçamento

```mermaid
sequenceDiagram
    autonumber
    actor OP as Operador
    participant GW as API Gateway
    participant API as Pod da API
    participant DB as RDS
    participant SES as SES
    actor CLI as Cliente

    OP->>GW: POST /api/work-orders<br/>Bearer JWT
    GW->>API: POST /work-orders
    API->>API: Auth + RequireRoles(admin, employee)
    API->>DB: INSERT work_orders<br/>status = RECEBIDA, code único
    DB-->>API: work_order
    API-->>OP: 201 {id, code, status}

    OP->>GW: POST /api/work-orders/{id}/services
    GW->>API: POST /work-orders/{id}/services
    API->>DB: valida status permite alterar itens
    API->>DB: INSERT work_order_services<br/>com SNAPSHOT de título, preço e tempo
    Note right of DB: o preço do catálogo pode mudar amanhã,<br/>o da OS não — ver ADR-0010
    API-->>OP: 201 [serviços]

    OP->>GW: PUT /api/work-orders/{id}<br/>status = EM_DIAGNOSTICO
    API->>DB: TransitionStatus (RECEBIDA → EM_DIAGNOSTICO)

    OP->>GW: PUT /api/work-orders/{id}<br/>status = AGUARDANDO_APROVACAO
    API->>DB: TransitionStatus
    API->>DB: soma dos snapshots + faltas de insumo
    Note right of API: insumo em falta acrescenta<br/>2 dias ao prazo estimado
    API->>SES: envia orçamento com link de<br/>aprovação por serviço e "aprovar tudo"
    API->>DB: UPDATE work_orders<br/>total_estimated_price_cents, quote_sent_at
    SES-->>CLI: e-mail do orçamento
```

## 2. Decisão do cliente

O cliente não tem conta nem token. Ele clica no link do e-mail, que carrega o
UUID do item — um identificador não adivinhável.

```mermaid
sequenceDiagram
    autonumber
    actor CLI as Cliente
    participant CF as CloudFront
    participant API as Pod da API
    participant DB as RDS
    participant SES as SES
    actor COM as Compras

    CLI->>CF: GET /api/public/approvals/services/{wosId}/approve
    CF->>API: rota pública, sem Authorization
    API->>DB: UPDATE work_order_services<br/>approval_status = APROVADO

    API->>DB: SELECT todos os serviços da OS
    alt ainda há serviço PENDENTE
        API-->>CLI: 200 — aguarda as demais decisões
    else todas decididas
        alt ao menos um APROVADO
            API->>DB: TransitionStatus → APROVADO
            API->>DB: recalcula total apenas com os aprovados
            API->>DB: procura insumos com estoque insuficiente
            opt há falta de insumo
                API->>SES: alerta de compra
                SES-->>COM: e-mail para compras@oficina.com
            end
        else todas REPROVADAS
            API->>DB: TransitionStatus → CANCELADA
        end
        API->>SES: e-mail de mudança de status
        SES-->>CLI: notificação
        API-->>CLI: 200
    end
```

Em paralelo, o cliente consulta o andamento sem autenticação, provando posse do
documento:

```mermaid
sequenceDiagram
    actor CLI as Cliente
    participant API as Pod da API
    participant DB as RDS
    CLI->>API: GET /public/work-orders/{code}?document=CPF
    API->>DB: SELECT ... WHERE code = $1 AND customers.document = $2
    alt não confere
        API-->>CLI: 404 (não distingue "não existe" de "não é seu")
    else confere
        API-->>CLI: 200 {status, serviços, prazo}
    end
```

## 3. Execução

```mermaid
sequenceDiagram
    autonumber
    actor OP as Operador
    participant API as Pod da API
    participant DB as RDS
    participant SES as SES
    actor CLI as Cliente

    OP->>API: PUT /work-orders/{id}<br/>status = EM_EXECUCAO
    API->>DB: TransitionStatus (APROVADO → EM_EXECUCAO)<br/>grava started_at
    API->>SES: notificação de status
    SES-->>CLI: e-mail

    loop para cada serviço aprovado
        OP->>API: PUT /work-orders/{id}/services/{wosId}/start
        API->>DB: valida OS em EM_EXECUCAO<br/>e serviço APROVADO + PENDENTE
        API->>DB: status = EM_EXECUCAO, started_at = now
        OP->>API: PUT /work-orders/{id}/services/{wosId}/finalize
        API->>DB: status = FINALIZADO, finished_at = now
    end

    OP->>API: PUT /work-orders/{id}<br/>status = FINALIZADA
    API->>DB: grava finished_at
    API->>SES: notificação
    SES-->>CLI: "veículo pronto"

    OP->>API: PUT /work-orders/{id}<br/>status = ENTREGUE
    API->>DB: grava delivered_at
```

## Os carimbos de tempo alimentam as métricas

`received_at`, `quote_sent_at`, `approved_at`, `started_at`, `finished_at` e
`delivered_at` estão em `work_orders`; `started_at` e `finished_at` também em
`work_order_services`. É deles que sai o **tempo médio de execução por status**
exigido no dashboard, sem depender de tabela de histórico. Ver
[RFC-0004](../rfc/0004-estrategia-de-observabilidade.md) e
[banco de dados](../banco-de-dados.md).
