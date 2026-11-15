locals {
  name = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Layer       = "platform"

    env = var.environment
  }

  ssm_prefix = "/${var.project}/${var.environment}"

  is_production = var.environment == "prod"

  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  node_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id

  service_repositories = ["os-service", "billing-service", "execution-service"]

  service_deployer_group = "oficina-service-deployers"
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}
