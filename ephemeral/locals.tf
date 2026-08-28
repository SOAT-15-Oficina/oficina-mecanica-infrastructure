locals {
  name = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Layer       = "ephemeral"
  }

  ssm_prefix = "/${var.project}/${var.environment}"

  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  app_labels = {
    "app.kubernetes.io/name"      = var.project
    "app.kubernetes.io/component" = "api"
  }

  api_deployment_name = "api"

  # Placeholder do Deployment. Sobe instantaneamente, nao serve nada e nao
  # confunde ninguem com um 200 falso -- ao contrario de um nginx.
  placeholder_image = "registry.k8s.io/pause:3.9"
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}
