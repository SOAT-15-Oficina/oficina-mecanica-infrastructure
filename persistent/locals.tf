locals {
  name = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Layer       = "persistent"
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
  repositories = {
    infrastructure = "${var.project}-infrastructure"
    monolith       = "${var.project}-monolith"
    serverless     = "${var.project}-serverless"
    frontend       = "${var.project}-frontend"
  }
}
