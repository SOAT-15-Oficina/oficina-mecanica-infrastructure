locals {
  name = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Layer       = "ephemeral"

    # Duplica `Environment` de proposito. O Datadog importa as tags da AWS como
    # vem, entao `Environment` viraria `environment:prod` -- enquanto o agente
    # no cluster e o APM publicam `env:prod`. Sem esta tag, uma consulta que
    # cruza metrica de RDS com metrica de pod precisaria de dois filtros
    # diferentes para dizer a mesma coisa.
    env = var.environment
  }

  ssm_prefix = "/${var.project}/${var.environment}"

  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  app_labels = {
    "app.kubernetes.io/name"      = var.project
    "app.kubernetes.io/component" = "api"
  }

  api_deployment_name = "api"

  # SG que o EKS anexa as instancias do node group. Nao e o SG do control
  # plane: e o mesmo aplicado aos nos e, por consequencia, aos pods, ja que o
  # VPC CNI usa IPs secundarios da ENI do no.
  node_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id

  # Placeholder do Deployment. Sobe instantaneamente, nao serve nada e nao
  # confunde ninguem com um 200 falso -- ao contrario de um nginx.
  placeholder_image = "registry.k8s.io/pause:3.9"

  # A ponte entre o ALB do Terraform e os pods: o AWS Load Balancer Controller
  # reconcilia este CR mantendo o target group populado com os IPs dos pods do
  # Service, sem criar balanceador nenhum.
  target_group_binding_manifest = yamlencode({
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "TargetGroupBinding"

    metadata = {
      name      = "api"
      namespace = kubernetes_namespace.workshop.metadata[0].name
    }

    spec = {
      targetGroupARN = aws_lb_target_group.api.arn
      targetType     = "ip"

      serviceRef = {
        name = kubernetes_service.api.metadata[0].name
        port = 8080
      }

      networking = {
        ingress = [{
          from  = [{ securityGroup = { groupID = aws_security_group.alb.id } }]
          ports = [{ protocol = "TCP", port = 8080 }]
        }]
      }
    }
  })
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}
