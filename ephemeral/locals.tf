locals {
  name = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Layer       = "ephemeral"

    env = var.environment
  }

  ssm_prefix = "/${var.project}/${var.environment}"

  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # SG que o EKS anexa as instancias do node group. Nao e o SG do control
  # plane: e o mesmo aplicado aos nos e, por consequencia, aos pods, ja que o
  # VPC CNI usa IPs secundarios da ENI do no.
  node_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id

  service_repositories = ["os-service", "billing-service", "execution-service"]

  service_deployer_group = "oficina-service-deployers"
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}
