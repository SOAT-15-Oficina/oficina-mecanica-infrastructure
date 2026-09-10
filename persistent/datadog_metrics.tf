# Metricas geradas a partir de log.
#
# POR QUE ESTA CAMADA EXISTE. Os paineis de negocio da fase -- volume diario de
# ordens de servico, tempo medio por status, erros de integracao -- sao
# perguntas sobre EVENTOS, e os eventos so existem no log da aplicacao. Consultar
# log direto no painel funciona, mas e caro, tem retencao curta e nao serve de
# base para alerta com limiar.
#
# Uma metrica de log resolve os tres: o Datadog conta o evento no momento da
# ingestao e guarda so o numero, com a retencao de metrica (15 meses) em vez da
# de log (dias). Os paineis e os monitores consultam a METRICA; o log fica para
# a investigacao.
#
# CONTRATO COM A APLICACAO. Toda consulta abaixo depende de dois campos do JSON
# emitido pelo `slog` (ADR-0011):
#
#   @event   nome do evento de dominio -- `work_order.created` e companhia
#   @env     ambiente -- `prod` ou `homolog`
#
# O nome do evento vai num campo PROPRIO, e nao no `msg`: `msg` e texto para
# humano e muda na primeira refatoracao; `@event` e identificador e nao muda.
# Enquanto o monolito nao emitir esses campos, as metricas existem e ficam em
# zero -- que e o estado correto, e nao um erro.

locals {
  # Aparece em toda consulta: sem isto, um evento de homologacao contaria no
  # painel de producao, porque a organizacao do Datadog e uma so.
  dd_log_scope = "@env:${local.dd_env}"

  # Contadores simples: um evento, uma metrica. O agrupamento por `@service`
  # separa monolito de Lambda sem precisar de uma metrica para cada.
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

  # `oficina.` prefixando tudo: no espaco de nomes de metricas do Datadog
  # convivem as da AWS (`aws.`), as do cluster (`kubernetes.`) e as de traco
  # (`trace.`). Um prefixo proprio deixa obvio de onde a metrica veio.
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

# Tempo medio de execucao por status -- painel exigido pela fase.
#
# Distribuicao, e nao contagem: a media sozinha esconde a cauda, e e a cauda que
# indica ordem esquecida em diagnostico. Com distribuicao o mesmo dado responde
# media, p95 e maximo sem precisar de outra metrica.
#
# `@duration_ms` e o tempo que a OS passou no status ANTERIOR, e `@to` e o
# status em que ela acabou de entrar -- entao agrupar por `@to` da exatamente
# "tempo medio ate sair de cada status".
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

# Erros e falhas nas integracoes -- o terceiro painel exigido pela fase.
#
# Uma metrica so, agrupada por `@integration`, em vez de uma por integracao: o
# painel quer "erros nas integracoes" como um todo, e uma integracao nova
# aparece no grafico sem precisar de PR neste repositorio.
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

# Latencia vista pela propria aplicacao, a partir da linha de acesso do
# middleware (ADR-0011). Redundante com o APM quando ele estiver instrumentado
# -- e de proposito: e ela que sustenta o painel de latencia por rota enquanto o
# traco nao existir, e continua util depois como contra-prova.
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
