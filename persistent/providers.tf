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
