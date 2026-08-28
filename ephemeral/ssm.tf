# Parametros produzidos por esta camada. Somados aos da camada persistente,
# formam o contrato completo que os repositorios de aplicacao consomem.
#
# Sao recriados a cada bring-up com os novos identificadores: os pipelines nunca
# hardcodam nome de cluster, namespace ou nome de deployment.
locals {
  ephemeral_parameters = {
    eks_cluster_name     = aws_eks_cluster.main.name
    eks_cluster_endpoint = aws_eks_cluster.main.endpoint
    kube_namespace       = kubernetes_namespace.workshop.metadata[0].name
    api_deployment_name  = kubernetes_deployment.api.metadata[0].name
    api_service_name     = kubernetes_service.api.metadata[0].name
    database_endpoint    = aws_db_instance.main.address
    database_name        = aws_db_instance.main.db_name
    vpc_id               = aws_vpc.main.id
    private_subnet_ids   = join(",", aws_subnet.private[*].id)
    alb_dns_name         = aws_lb.internal.dns_name
  }
}

resource "aws_ssm_parameter" "ephemeral" {
  for_each = local.ephemeral_parameters

  name      = "${local.ssm_prefix}/${each.key}"
  type      = "String"
  value     = each.value
  overwrite = true
}
