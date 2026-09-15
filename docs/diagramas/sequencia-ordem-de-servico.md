# Ciclo de vida da ordem de serviço

O percurso completo: abertura, diagnóstico, orçamento por e-mail, decisão do
cliente e execução. Dois atores humanos com canais distintos. O operador usa
rotas autenticadas por JWT; o cliente usa links públicos recebidos por e-mail.

## Máquina de estados

A transição é validada no serviço de domínio. Qualquer salto fora deste mapa é
rejeitado com `ErrInvalidStatusTransition`, e o evento
`work_order.transition_rejected` é registrado em log
([ADR-0011](../adr/0011-logs-estruturados-com-correlacao.md)).

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

Itens só podem ser adicionados ou removidos nos estados `RECEBIDA`,
`EM_DIAGNOSTICO` ou `AGUARDANDO_APROVACAO`. Depois de aprovada, a composição da
OS está congelada, e os valores também ([ADR-0010](../adr/0010-snapshot-de-precos-na-ordem-de-servico.md)).

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
    Note right of DB: o preço do catálogo pode mudar amanhã,<br/>o da OS não. Ver ADR-0010
    API-->>OP: 201 [serviços]

    OP->>GW: PUT /api/work-orders/{id}<br/>status = EM_DIAGNOSTICO
    API->>DB: TransitionStatus (RECEBIDA para EM_DIAGNOSTICO)

    OP->>GW: PUT /api/work-orders/{id}<br/>status = AGUARDANDO_APROVACAO
    API->>DB: TransitionStatus
    API->>DB: soma dos snapshots + faltas de insumo
    Note right of API: insumo em falta acrescenta<br/>2 dias ao prazo estimado
    API->>SES: envia orçamento com link de<br/>aprovação por serviço e "aprovar tudo"
    API->>DB: UPDATE work_orders<br/>total_estimated_price_cents, quote_sent_at
    SES-->>CLI: e-mail do orçamento
```

O envio do e-mail acontece **dentro do handler**, sem fila. Falha do SES é
registrada em log com o evento `budget.send_failed` e **não** derruba a
operação de negócio. O racional e o custo aceito estão na
[ADR-0002](../adr/0002-comunicacao-sincrona-http.md).

## 2. Decisão do cliente

O cliente não tem conta nem token. Ele clica no link do e-mail, que carrega o
UUID do item, um identificador não adivinhável.

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
        API-->>CLI: 200, aguarda as demais decisões
    else todas decididas
        alt ao menos um APROVADO
            API->>DB: TransitionStatus para APROVADO
            API->>DB: recalcula total apenas com os aprovados
            API->>DB: procura insumos com estoque insuficiente
            opt há falta de insumo
                API->>SES: alerta de compra
                SES-->>COM: e-mail para compras@oficina.com
            end
        else todas REPROVADAS
            API->>DB: TransitionStatus para CANCELADA
        end
        API->>SES: e-mail de mudança de status
        SES-->>CLI: notificação
        API-->>CLI: 200
    end
```

O total da OS é recalculado **apenas com os itens aprovados**. Um item
reprovado permanece na tabela, com `approval_status = REPROVADO`, e fica fora
da soma.

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

A resposta 404 para os dois casos é intencional: distinguir "não existe" de
"não é seu" confirmaria a existência de uma OS a quem não tem o documento.

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
    API->>DB: TransitionStatus (APROVADO para EM_EXECUCAO)<br/>grava started_at
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

Cada item tem dois estados independentes: `approval_status`, que o cliente
muda, e `status`, que o mecânico muda. A razão de serem duas colunas, e não
uma, está no [modelo de dados](../banco-de-dados.md).

## Os carimbos de tempo alimentam as métricas

`received_at`, `quote_sent_at`, `approved_at`, `started_at`, `finished_at` e
`delivered_at` estão em `work_orders`. `started_at` e `finished_at` também
existem em `work_order_services`.

É desses carimbos que sai o **tempo médio de execução por status** exigido no
dashboard, sem depender de tabela de histórico. Foi o que permitiu remover a
tabela `work_order_service_status_history` do schema sem perder a métrica
([modelo de dados](../banco-de-dados.md), seção 4.2). Ver também [RFC-0004](../rfc/0004-estrategia-de-observabilidade.md).
