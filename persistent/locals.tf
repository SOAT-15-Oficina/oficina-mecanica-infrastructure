locals {
  name = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Layer       = "persistent"
  }

  ssm_prefix = "/${var.project}/${var.environment}"

  # Um repositorio, uma role, um conjunto minimo de permissoes.
  repositories = {
    infrastructure = "${var.project}-infrastructure"
    monolith       = "${var.project}-monolith"
    serverless     = "${var.project}-serverless"
    frontend       = "${var.project}-frontend"
  }
}
