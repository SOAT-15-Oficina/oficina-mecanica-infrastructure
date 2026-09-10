# Os dois paineis exigidos pela fase, um por arquivo.
#
# Separados de proposito, e nao um painel unico com tudo: quem investiga uma
# queda quer CPU, latencia e reinicio na mesma tela; quem responde "quantas
# ordens abriram hoje" nao quer nenhum dos tres. Misturar os dois publicos faz
# um painel que ninguem abre.
#
#   datadog_dashboard_operacional.tf -- saude do sistema. Fonte: agente no
#       cluster, integracao AWS, metricas de log e teste sintetico.
#   datadog_dashboard_negocio.tf -- os tres paineis que o enunciado nomeia:
#       volume diario de OS, tempo medio por status e erros nas integracoes.
#       Fonte: metricas de log (datadog_metrics.tf).
#
# `layout_type = "ordered"` com `reflow_type = "auto"` nos dois: a posicao de
# cada widget fica implicita na ordem em que aparece no arquivo. Coordenada
# explicita seria mais uma coisa a manter em sincronia a cada widget novo, sem
# ganho nenhum.

# Nomes e prefixos que os dois paineis compartilham.
#
# A camada efemera recria estes recursos a cada bring-up com os MESMOS nomes
# (todos derivados de local.name), e e isso que permite ao painel -- que e
# persistente -- apontar para eles sem depender do state dela.
locals {
  dd_rds_identifier   = local.name
  dd_lambda_name      = "${local.name}-auth"
  dd_api_id           = aws_apigatewayv2_api.main.id
  dd_kube_namespace   = "workshop"
  dd_dashboard_prefix = "${var.project} [${var.environment}]"
}
