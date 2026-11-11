locals {
  name = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Layer       = "persistent"

    env = var.environment
  }

  ssm_prefix = "/${var.project}/${var.environment}"

  # Convencao de promocao do time: `main` publica em producao, `hml` publica em
  # homologacao. Um ambiente novo herda a segunda regra ate que alguem passe
  # `deploy_branch` explicitamente.
  is_production = var.environment == "prod"

  deploy_branch      = coalesce(var.deploy_branch, local.is_production ? "main" : "hml")
  github_environment = coalesce(var.github_environment, local.is_production ? "production" : var.environment)

  # `coalesce` nao serve para bool: ele so aceita strings.
  manage_ses_identities = var.manage_ses_identities == null ? local.is_production : var.manage_ses_identities

  # Um repositorio, uma role, um conjunto minimo de permissoes.
  repositories = merge(
    {
      infrastructure = "${var.project}-infrastructure"
      serverless     = "${var.project}-serverless"
      frontend       = "${var.project}-frontend"
    },
    { for repo in keys(local.services) : repo => "${var.project}-${repo}" },
  )

  services = {
    "os-service"        = { short = "os", database = true, dynamodb = false, subscribes = true, internal_token = true }
    "billing-service"   = { short = "billing", database = true, dynamodb = false, subscribes = false, internal_token = false }
    "execution-service" = { short = "execution", database = false, dynamodb = true, subscribes = false, internal_token = false }
  }
}
