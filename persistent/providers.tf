provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}

# CloudFront exige que o certificado ACM esteja em us-east-1. O alias existe
# mesmo sem dominio proprio hoje, para que adicionar um depois nao vire refactor.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.common_tags
  }
}

# Painel, monitor e integracao sao recursos como qualquer outro -- so que a API
# e a do Datadog, e nao a da AWS.
#
# `validate` desligado quando a stack sobe sem Datadog: por padrao o provider
# valida as credenciais no INIT, antes de saber que nao ha nenhum recurso dele
# para criar, e um `datadog_enabled = false` sem chave morreria ali.
provider "datadog" {
  api_key  = var.datadog_api_key
  app_key  = var.datadog_app_key
  api_url  = "https://api.${var.datadog_site}/"
  validate = local.datadog_enabled
}
