# ADR-0016. Mercado Pago Checkout Pro, webhook validado por consulta

**Proposta** · 2026-11-11 · Origem [RFC-0006](../rfc/0006-microsservicos-e-saga.md)

**Contexto.** O enunciado exige cobrança integrada ao Mercado Pago. Antes da
Fase 4 não existia pagamento no sistema.

**Decisão.** Checkout Pro no ambiente de testes do Mercado Pago, operado pelo
Billing:

1. Ao receber `billing.request-payment`, cria preferência
   (`POST /checkout/preferences`) com os itens aprovados,
   `external_reference = quote_id`, `notification_url` no webhook do Billing e
   `expiration_date_to` igual ao prazo de pagamento da Saga.
2. O link vai ao cliente por e-mail e aparece na consulta pública da OS.
3. O webhook valida `x-signature`, **descarta o corpo** e consulta
   `GET /v1/payments/{id}`. Só `approved` confirma; `rejected` e `cancelled`
   falham.
4. Estorno por `POST /v1/payments/{id}/refunds` com chave de idempotência igual
   ao `message_id` do comando.
5. Restrição única: no máximo um pagamento `approved` por orçamento.

Access token no Secrets Manager. Testes usam um fake HTTP do Mercado Pago.

## Alternativas descartadas

| Opção | Motivo do descarte |
|---|---|
| Checkout Transparente | o formulário de cartão viveria no nosso front, trazendo escopo de PCI |
| PIX direto (QR code) | não cobre cartão; Checkout Pro já oferece PIX entre os meios |
| Confiar no corpo do webhook | qualquer um que descubra a URL confirmaria pagamento |

## Consequências

| Ganhos | Custos |
|---|---|
| nenhum dado de cartão passa pelo sistema | o webhook precisa de URL pública: o caminho entra no API Gateway |
| confirmação imune a webhook forjado | uma chamada extra ao Mercado Pago por notificação |
| estorno seguro contra reenvio da Saga | demonstração depende das contas de teste do Mercado Pago |
