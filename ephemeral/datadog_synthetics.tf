# Teste sintetico do endpoint publico.
#
# Vive aqui, e nao na camada persistente, porque o que ele mede e uma
# propriedade do ambiente EFEMERO: existe enquanto o ambiente existe.
#
# Na camada persistente ele ficava `live` 24 horas por dia, inclusive com o
# ambiente destruido. Como o dominio do CloudFront e o API Gateway sobrevivem ao
# tear-down mas as rotas e o VPC Link nao, cada execucao recebia 404, falhava a
# assertion de status 200 e entrava na conta do painel. O widget de uptime e uma
# razao acumulada na janela (execucoes que passaram / total), entao ele exibia
# 0% depois de qualquer periodo desligado -- medindo corretamente uma pergunta
# que ninguem fez. O monitor priority 1 tambem disparava por ambiente desligado
# de proposito.
#
# Criado pelo bring-up e destruido pelo tear-down, "uptime" passa a significar
# uptime enquanto o ambiente devia estar no ar.

data "aws_ssm_parameter" "datadog_notify" {
  name = "${local.ssm_prefix}/datadog_notify"
}

locals {
  dd_synthetics_enabled = local.datadog_enabled && var.datadog_app_key != ""

  dd_public_base_url = nonsensitive(data.aws_ssm_parameter.public_base_url.value)

  dd_notify_raw = nonsensitive(data.aws_ssm_parameter.datadog_notify.value)
  dd_notify     = local.dd_notify_raw == "unset" ? "" : local.dd_notify_raw

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
    url    = "${local.dd_public_base_url}/api/ping"

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
    pods. Se o bring-up acabou de rodar, o Deployment pode ainda estar com a
    imagem `pause`: o 200 so aparece depois do rollout do -monolith.

    Ambiente: ${var.environment} | Painel: ${var.project} [${var.environment}] Operacional
    Definido em ephemeral/datadog_synthetics.tf -- mude por PR, nao pela interface.
    ${local.dd_notify}
  EOT
}
