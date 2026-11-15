# ADR-0014. SNS FIFO + SQS FIFO com outbox e consumidor idempotente

**Proposta** · 2026-11-11 · Origem [RFC-0006](../rfc/0006-microsservicos-e-saga.md)

**Contexto.** A Saga ([ADR-0013](./0013-saga-orquestrada-no-os-service.md))
depende de mensagens entre serviços que não podem se perder, duplicar efeito
nem chegar fora de ordem dentro de uma OS.

**Decisão.**

- **Comandos** vão direto para a fila FIFO do participante
  (`billing-inbox.fifo`, `execution-inbox.fifo`).
- **Eventos** saem no tópico SNS FIFO do emissor (`billing-events.fifo`,
  `execution-events.fifo`); o `os-inbox.fifo` assina os dois.
- `MessageGroupId = work_order_id`: ordem garantida por OS, paralelismo entre
  OS diferentes.
- DLQ por fila, `maxReceiveCount = 5`, com monitor de profundidade.
- **Outbox transacional** em todos os serviços: estado e mensagem gravados na
  mesma transação; um publicador no processo envia e marca como publicado.
- **Consumidor idempotente:** `message_id` gravado em `processed_messages` na
  mesma transação do efeito.
- Envelope único com `message_id`, `type`, `version`, `saga_id`,
  `work_order_id`, `correlation_id`, `causation_id` e `occurred_at`; contexto de
  trace em message attributes.
- Quem consome a fila é o dono dela e a cria no próprio Terraform.

## Alternativas descartadas

| Opção | Motivo do descarte |
|---|---|
| RabbitMQ no cluster | um broker com estado para operar, persistir e monitorar dentro do EKS |
| Kafka / MSK | custo fixo alto e operação desproporcional ao volume de uma oficina |
| Filas Standard | sem ordem por OS; `diagnosis-completed` poderia chegar antes de `diagnosis-started` |
| Publicar direto após o `COMMIT` | um pod que morre entre o `COMMIT` e o `Publish` deixa a saga parada para sempre |

## Consequências

| Ganhos | Custos |
|---|---|
| nenhum broker para operar; IAM por serviço via IRSA | FIFO limita a 300 msg/s por grupo sem batching, muito acima do necessário |
| LocalStack reproduz tudo no CI | outbox e idempotência são código novo em três serviços |
| novo assinante entra sem mudar o emissor | entrega pelo menos uma vez exige disciplina em todo consumidor |
