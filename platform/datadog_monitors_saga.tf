resource "datadog_monitor" "saga_dlq_depth" {
  count = local.datadog_enabled ? 1 : 0

  name = "[${var.environment}] Mensagem da Saga parada em DLQ"
  type = "metric alert"

  query = "max(last_5m):max:aws.sqs.approximate_number_of_messages_visible{queuename:${local.dd_queue_prefix}-*-inbox-dlq.fifo} by {queuename} > 0"

  message = <<-EOT
    {{#is_alert}}
    {{queuename.name}} tem {{value}} mensagem(ns). Uma mensagem so chega a DLQ
    depois de 5 recebimentos sem sucesso ou quando o envelope e invalido: a OS
    correspondente esta parada no passo atual da Saga.

    Onde olhar: o `work_order_id` esta no corpo da mensagem; com ele, consulte
    `GET /work-orders/{id}/saga` e filtre o log por `@work_order_id`. Corrigida a
    causa, devolva a mensagem a fila de origem com o redrive do SQS.
    {{/is_alert}}
    {{#is_recovery}}
    {{queuename.name}} esvaziou.
    {{/is_recovery}}
    ${local.dd_monitor_footer}
  EOT

  monitor_thresholds {
    critical = 0
  }

  priority       = 2
  notify_no_data = false
  include_tags   = true
  tags           = concat(local.dd_tags, ["signal:saga"])
}

resource "datadog_monitor" "saga_inbox_age" {
  count = local.datadog_enabled ? 1 : 0

  name = "[${var.environment}] Inbox da Saga com mensagem antiga"
  type = "metric alert"

  query = "max(last_10m):max:aws.sqs.approximate_age_of_oldest_message{queuename:${local.dd_queue_prefix}-*-inbox.fifo} by {queuename} > 300"

  message = <<-EOT
    {{#is_alert}}
    A mensagem mais antiga visivel em {{queuename.name}} tem {{value}}s. O
    consumidor faz long polling continuo, entao ninguem esta lendo esta fila:
    o servico dono dela caiu, esta sem replicas ou perdeu a permissao IRSA.
    {{/is_alert}}
    ${local.dd_monitor_footer}
  EOT

  monitor_thresholds {
    critical = 300
    warning  = 120
  }

  priority       = 2
  notify_no_data = false
  include_tags   = true
  tags           = concat(local.dd_tags, ["signal:saga"])
}

resource "datadog_monitor" "saga_log_errors" {
  count = local.datadog_enabled ? 1 : 0

  name = "[${var.environment}] Erro na Saga"
  type = "log alert"

  query = "logs(\"${local.dd_log_scope} status:error @event:saga.*\").index(\"*\").rollup(\"count\").last(\"5m\") > 0"

  message = <<-EOT
    {{#is_alert}}
    {{value}} erro(s) da Saga em ${var.environment} nos ultimos 5 minutos.

    Filtre o log por `@event:saga.*` e pegue o `@saga_id` ou o `@work_order_id`
    de uma das linhas: o estado persistido da saga (passo, tentativas e motivo
    da falha) aparece em `GET /work-orders/{id}/saga`.
    {{/is_alert}}
    ${local.dd_monitor_footer}
  EOT

  monitor_thresholds {
    critical = 0
  }

  priority       = 2
  notify_no_data = false
  include_tags   = true
  tags           = concat(local.dd_tags, ["signal:saga"])
}
