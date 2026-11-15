# Ciclo de vida da ordem de serviço

Na Fase 4 a OS atravessa três serviços e é coordenada por uma Saga orquestrada
no OS Service. **A fonte de verdade deste fluxo é a
[RFC-0006](../rfc/0006-microsservicos-e-saga.md)**:

| Assunto | Onde |
|---|---|
| Máquina de estados da OS (com `AGUARDANDO_PAGAMENTO`) | [RFC-0006, seção 3](../rfc/0006-microsservicos-e-saga.md#3-máquina-de-estados-da-os) |
| Passos, pivô e caminho feliz | [RFC-0006, seção 4](../rfc/0006-microsservicos-e-saga.md#4-saga-orquestrada) |
| Compensações (reprovação, pagamento recusado, bancada recusou) | [RFC-0006, seção 4](../rfc/0006-microsservicos-e-saga.md#falhas-e-compensação) |
| Prazos e reenvio | [RFC-0006, seção 4](../rfc/0006-microsservicos-e-saga.md#prazos-e-repetição) |
| Filas, tópicos e catálogo de mensagens | [RFC-0006, seção 5](../rfc/0006-microsservicos-e-saga.md#5-mensageria) |
| Mercado Pago | [RFC-0006, seção 6](../rfc/0006-microsservicos-e-saga.md#6-mercado-pago) |

Este arquivo mostra só o que a RFC não desenha: **por qual porta cada ator
entra**. Todas as chamadas passam por CloudFront e API Gateway; o prefixo
decide o serviço no listener do ALB interno.

```mermaid
sequenceDiagram
    autonumber
    actor OP as Operador (painel, JWT)
    actor CLI as Cliente (e-mail)
    participant MP as Mercado Pago
    participant OS as OS Service<br/>/api/*
    participant EX as Execution<br/>/api/execution/*
    participant BI as Billing<br/>/api/billing/*

    OP->>OS: POST /api/work-orders
    Note over OS: OS RECEBIDA + saga STARTED<br/>execution.schedule-diagnosis
    OP->>EX: POST /api/execution/tickets/{id}/diagnosis/start
    OP->>OS: POST /api/work-orders/{id}/services
    OP->>EX: POST /api/execution/tickets/{id}/diagnosis/complete
    Note over OS,BI: billing.create-quote → e-mail com links
    CLI->>BI: GET /api/billing/public/quotes/{id}/approve-all
    Note over OS,BI: billing.request-payment → e-mail com link de pagamento
    CLI->>MP: paga no Checkout Pro
    MP->>BI: POST /api/billing/webhooks/mercadopago (x-signature)
    Note over OS,EX: payment-confirmed → execution.enqueue-repair (pivô)
    OP->>EX: POST /api/execution/tickets/{id}/repair/start
    OP->>EX: POST /api/execution/tickets/{id}/items/{item}/start e /finish
    Note over OS: repair-completed → FINALIZADA
    OP->>OS: POST /api/work-orders/{id}/deliver
    CLI->>OS: GET /api/public/work-orders/{code}?document=CPF<br/>status, histórico e payment_url
```

Consultas de acompanhamento pelo operador: `GET /api/work-orders/{id}/history`
(transições com causa e `message_id`) e `GET /api/work-orders/{id}/saga` (passo
atual, prazo, tentativas e compensações pendentes). O painel "Saga" do Datadog
(`platform/datadog_dashboard_saga.tf`) mostra o mesmo de forma agregada.

Para percorrer o fluxo localmente, incluindo o pagamento pelo Mercado Pago
falso, veja [`local/README.md`](../../local/README.md).
