locals {
  dd_monitor_footer = <<-EOT

    Ambiente: ${var.environment} | Painel: ${var.project} [${var.environment}] Operacional
    Definido em persistent/datadog_monitors.tf -- mude por PR, nao pela interface.
    ${local.dd_notify}
  EOT
}

resource "datadog_monitor" "work_order_processing_failure" {
  count = local.datadog_enabled ? 1 : 0

  name = "[${var.environment}] Falha no processamento de ordem de servico"
  type = "log alert"

  query = "logs(\"${local.dd_log_scope} (@event:work_order.transition_rejected OR (status:error @work_order_id:*))\").index(\"*\").rollup(\"count\").last(\"5m\") > 0"

  message = <<-EOT
    {{#is_alert}}
    Ordem de servico falhando no processamento em ${var.environment}: {{value}} ocorrencia(s) em 5 minutos.

    Onde olhar: filtre o log por `@event:work_order.transition_rejected` ou por
    `status:error @work_order_id:*` e pegue o `@request_id` de uma das linhas --
    ele leva ao rastro completo, incluindo o access log do API Gateway.
    {{/is_alert}}
    {{#is_recovery}}
    Sem novas falhas de processamento nos ultimos 5 minutos.
    {{/is_recovery}}
    ${local.dd_monitor_footer}
  EOT

  monitor_thresholds {
    critical = 0
  }

  priority       = 2
  notify_no_data = false
  include_tags   = true
  tags           = concat(local.dd_tags, ["signal:work-order"])
}

resource "datadog_monitor" "budget_send_failed" {
  count = local.datadog_enabled ? 1 : 0

  name = "[${var.environment}] Falha no envio de orcamento"
  type = "log alert"

  query = "logs(\"${local.dd_log_scope} @event:budget.send_failed\").index(\"*\").rollup(\"count\").last(\"15m\") >= 1"

  message = <<-EOT
    {{#is_alert}}
    {{value}} orcamento(s) nao chegaram ao cliente em ${var.environment} nos ultimos 15 minutos.

    O envio passa pelo SES. Verifique, nesta ordem: o `@error` da linha de log, o
    painel de bounces do configuration set e se o remetente continua verificado.
    {{/is_alert}}
    ${local.dd_monitor_footer}
  EOT

  monitor_thresholds {
    critical = 1
  }

  priority       = 2
  notify_no_data = false
  include_tags   = true
  tags           = concat(local.dd_tags, ["signal:integration"])
}

resource "datadog_monitor" "api_latency" {
  count = local.datadog_enabled ? 1 : 0

  name = "[${var.environment}] Latencia da API degradada (p95 > 1s)"
  type = "metric alert"

  query = "percentile(last_10m):p95:oficina.http_request_duration{env:${local.dd_env},service:${local.dd_services.api}} > 1000"

  message = <<-EOT
    {{#is_alert}}
    p95 da API em {{value}}ms nos ultimos 10 minutos (limiar: 1000ms).

    Cruze com o painel operacional: se a CPU dos pods estiver no limite, e
    escala; se so uma rota subiu, e consulta ao banco.
    {{/is_alert}}
    ${local.dd_monitor_footer}
  EOT

  monitor_thresholds {
    critical = 1000
    warning  = 700
  }

  priority = 3

  require_full_window = true
  notify_no_data      = false
  include_tags        = true
  tags                = concat(local.dd_tags, ["signal:latency"])
}

resource "datadog_monitor" "api_error_rate" {
  count = local.datadog_enabled ? 1 : 0

  name = "[${var.environment}] Taxa de 5xx acima de 1%"
  type = "metric alert"

  query = "sum(last_5m):( sum:aws.apigateway.5xx{apiid:${local.dd_api_id}}.as_count() / sum:aws.apigateway.count{apiid:${local.dd_api_id}}.as_count() ) * 100 > 1"

  message = <<-EOT
    {{#is_alert}}
    {{value}}% das requisicoes em ${var.environment} responderam 5xx nos ultimos 5 minutos.

    Se a aplicacao NAO registrou erro no mesmo periodo, o 5xx nasceu antes dela:
    olhe os targets do ALB e as rotas do API Gateway.
    {{/is_alert}}
    ${local.dd_monitor_footer}
  EOT

  monitor_thresholds {
    critical = 1
  }

  priority       = 2
  notify_no_data = false
  include_tags   = true
  tags           = concat(local.dd_tags, ["signal:errors"])
}

resource "datadog_monitor" "hpa_at_ceiling" {
  count = local.datadog_enabled ? 1 : 0

  name = "[${var.environment}] HPA no teto de replicas"
  type = "metric alert"

  query = "min(last_15m):max:kubernetes_state.hpa.current_replicas{env:${local.dd_env},kube_namespace:${local.dd_kube_namespace}} >= 10"

  message = <<-EOT
    {{#is_alert}}
    O HPA esta em {{value}} replicas -- o teto -- ha 15 minutos. Acima disto o
    sistema nao tem mais para onde escalar: a proxima onda de trafego vira fila.

    Decisao: subir `max_replicas` (ephemeral/k8s.tf) ou aumentar o node group.
    {{/is_alert}}
    ${local.dd_monitor_footer}
  EOT

  monitor_thresholds {
    critical = 10
    warning  = 8
  }

  priority       = 3
  notify_no_data = false
  include_tags   = true
  tags           = concat(local.dd_tags, ["signal:capacity"])
}

resource "datadog_monitor" "pod_restarts" {
  count = local.datadog_enabled ? 1 : 0

  name = "[${var.environment}] Pod reiniciando"
  type = "metric alert"

  query = "change(max(last_15m),last_15m):max:kubernetes_state.container.restarts{env:${local.dd_env},kube_namespace:${local.dd_kube_namespace}} by {pod_name} >= 3"

  message = <<-EOT
    {{#is_alert}}
    {{pod_name.name}} reiniciou {{value}} vezes em 15 minutos.

    Quase sempre e uma de tres: OOMKilled (memoria acima do limite), liveness
    probe falhando porque /ping nao responde, ou a imagem nao sobe.
    {{/is_alert}}
    ${local.dd_monitor_footer}
  EOT

  monitor_thresholds {
    critical = 3
  }

  priority       = 3
  notify_no_data = false
  include_tags   = true
  tags           = concat(local.dd_tags, ["signal:stability"])
}

resource "datadog_monitor" "database_connections" {
  count = local.datadog_enabled ? 1 : 0

  name = "[${var.environment}] Conexoes do banco perto do limite"
  type = "metric alert"

  query = "avg(last_10m):avg:aws.rds.database_connections{dbinstanceidentifier:${local.dd_rds_identifier}} > ${floor(var.database_max_connections * 0.8)}"

  message = <<-EOT
    {{#is_alert}}
    {{value}} conexoes abertas, contra um teto de ${var.database_max_connections}.

    Cada pod da API abre ate DATABASE_MAX_CONNECTIONS (5) e o HPA vai a 10
    replicas; some a Lambda de auth. Se o numero nao fecha com isso, ha conexao
    vazando.
    {{/is_alert}}
    ${local.dd_monitor_footer}
  EOT

  monitor_thresholds {
    critical = floor(var.database_max_connections * 0.8)
    warning  = floor(var.database_max_connections * 0.6)
  }

  priority       = 2
  notify_no_data = false
  include_tags   = true
  tags           = concat(local.dd_tags, ["signal:database"])
}

resource "datadog_monitor" "database_storage" {
  count = local.datadog_enabled ? 1 : 0

  name = "[${var.environment}] Espaco livre do banco abaixo de 20%"
  type = "metric alert"

  query = "avg(last_15m):avg:aws.rds.free_storage_space{dbinstanceidentifier:${local.dd_rds_identifier}} < ${var.database_free_storage_alert_bytes}"

  message = <<-EOT
    {{#is_alert}}
    Restam {{value}} bytes livres no RDS de ${var.environment}.

    O storage autoescala ate 50GB (ephemeral/rds.tf), entao isto raramente e
    urgente -- mas crescimento rapido em ambiente de teste costuma ser log ou
    seed rodando em laco.
    {{/is_alert}}
    ${local.dd_monitor_footer}
  EOT

  monitor_thresholds {
    critical = var.database_free_storage_alert_bytes
  }

  priority       = 4
  notify_no_data = false
  include_tags   = true
  tags           = concat(local.dd_tags, ["signal:database"])
}

resource "datadog_monitor" "agent_reporting" {
  count = local.datadog_enabled && var.datadog_alert_on_missing_agent ? 1 : 0

  name = "[${var.environment}] Agente do Datadog sem reportar"
  type = "metric alert"

  query = "avg(last_10m):avg:kubernetes.cpu.usage.total{env:${local.dd_env},kube_namespace:${local.dd_kube_namespace}} <= 0"

  message = <<-EOT
    {{#is_no_data}}
    Nenhuma metrica do cluster de ${var.environment} chegou nos ultimos 15 minutos.

    Ou o ambiente foi derrubado (confira o workflow tear-down) ou o agente caiu.
    Enquanto isso durar, NENHUM outro alerta deste ambiente e confiavel.
    {{/is_no_data}}
    {{#is_recovery}}
    O cluster de ${var.environment} voltou a reportar.
    {{/is_recovery}}
    ${local.dd_monitor_footer}
  EOT

  monitor_thresholds {
    critical = 0
  }

  priority          = 3
  notify_no_data    = true
  no_data_timeframe = 15
  include_tags      = true
  tags              = concat(local.dd_tags, ["signal:meta"])
}
