locals {
  dd_synthetics_enabled = local.datadog_enabled && var.datadog_app_key != ""

  dd_synthetics_tags = [
    "env:${var.environment}",
    "project:${var.project}",
    "managed_by:terraform",
    "check:api-ping",
  ]
}

resource "datadog_synthetics_test" "ping" {
  count = local.dd_synthetics_enabled ? 1 : 0

  name    = "[${var.environment}] Healthcheck publico de /api/ping"
  type    = "api"
  subtype = "http"
  status  = "live"

  locations = ["aws:${var.region}"]

  tags = local.dd_synthetics_tags

  request_definition {
    method = "GET"
    url    = "${local.public_base_url}/ping"

    timeout = 10
  }

  assertion {
    type     = "statusCode"
    operator = "is"
    target   = "200"
  }

  assertion {
    type     = "body"
    operator = "contains"
    target   = "Pong"
  }

  assertion {
    type     = "responseTime"
    operator = "lessThan"
    target   = "3000"
  }

  options_list {
    tick_every = 300

    monitor_name     = "[${var.environment}] API publica indisponivel"
    monitor_priority = 1

    retry {
      count    = 1
      interval = 300
    }

    monitor_options {
      renotify_interval = 60
    }
  }

  message = <<-EOT
    A URL publica de ${var.environment} parou de responder.

    Ordem de checagem: CloudFront -> API Gateway -> VPC Link -> ALB interno ->
    pods. Se o bring-up acabou de rodar, o 200 so aparece depois do deploy do
    oficina-mecanica-os-service, que cria a regra padrao no listener.

    Ambiente: ${var.environment} | Painel: ${var.project} [${var.environment}] Operacional
    Definido em platform/datadog_synthetics.tf -- mude por PR, nao pela interface.
    ${local.dd_notify}
  EOT
}
