locals {
  dd_log_scope = "@env:${local.dd_env}"

  datadog_event_counters = {
    "work_order.created"             = "Ordens de servico abertas"
    "work_order.status_changed"      = "Transicoes de status aceitas"
    "work_order.transition_rejected" = "Transicoes de status recusadas"
    "budget.sent"                    = "Orcamentos enviados"
    "budget.send_failed"             = "Falhas de envio de orcamento"
    "approval.decided"               = "Decisoes do cliente sobre o orcamento"
    "purchase_alert.sent"            = "Alertas de falta de insumo"
    "auth.login_failed"              = "Tentativas de login recusadas"
  }
}

resource "datadog_logs_metric" "event" {
  for_each = local.datadog_enabled ? local.datadog_event_counters : {}

  name = "oficina.${replace(each.key, ".", "_")}"

  filter {
    query = "${local.dd_log_scope} @event:${each.key}"
  }

  compute {
    aggregation_type = "count"
  }

  dynamic "group_by" {
    for_each = toset(["service", "env"])

    content {
      path     = "@${group_by.value}"
      tag_name = group_by.value
    }
  }
}

resource "datadog_logs_metric" "work_order_stage_duration" {
  count = local.datadog_enabled ? 1 : 0

  name = "oficina.work_order_stage_duration"

  filter {
    query = "${local.dd_log_scope} @event:work_order.status_changed @duration_ms:*"
  }

  compute {
    aggregation_type    = "distribution"
    path                = "@duration_ms"
    include_percentiles = true
  }

  group_by {
    path     = "@from"
    tag_name = "from"
  }

  group_by {
    path     = "@to"
    tag_name = "to"
  }

  group_by {
    path     = "@env"
    tag_name = "env"
  }
}

resource "datadog_logs_metric" "integration_error" {
  count = local.datadog_enabled ? 1 : 0

  name = "oficina.integration_error"

  filter {
    query = "${local.dd_log_scope} status:error @integration:*"
  }

  compute {
    aggregation_type = "count"
  }

  group_by {
    path     = "@integration"
    tag_name = "integration"
  }

  group_by {
    path     = "@service"
    tag_name = "service"
  }

  group_by {
    path     = "@env"
    tag_name = "env"
  }
}

resource "datadog_logs_metric" "http_request_duration" {
  count = local.datadog_enabled ? 1 : 0

  name = "oficina.http_request_duration"

  filter {
    query = "${local.dd_log_scope} @duration_ms:* @route:*"
  }

  compute {
    aggregation_type    = "distribution"
    path                = "@duration_ms"
    include_percentiles = true
  }

  group_by {
    path     = "@route"
    tag_name = "route"
  }

  group_by {
    path     = "@status"
    tag_name = "status"
  }

  group_by {
    path     = "@service"
    tag_name = "service"
  }

  group_by {
    path     = "@env"
    tag_name = "env"
  }
}
