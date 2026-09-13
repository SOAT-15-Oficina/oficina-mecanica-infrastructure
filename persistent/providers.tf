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

provider "datadog" {
  api_key  = var.datadog_api_key
  app_key  = var.datadog_app_key
  api_url  = "https://api.${var.datadog_site}/"
  validate = local.datadog_enabled
}
