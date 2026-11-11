# Parametros produzidos por esta camada. Somados aos da camada persistente,
# formam o contrato completo que os repositorios de aplicacao consomem.
#
# Sao recriados a cada bring-up com os novos identificadores: os pipelines nunca
# hardcodam nome de cluster, namespace ou nome de deployment.
locals {
  ephemeral_parameters = {
    eks_cluster_name           = aws_eks_cluster.main.name
    eks_cluster_endpoint       = aws_eks_cluster.main.endpoint
    eks_oidc_provider_arn      = aws_iam_openid_connect_provider.cluster.arn
    eks_node_security_group_id = local.node_security_group_id
    kube_namespace             = kubernetes_namespace.workshop.metadata[0].name
    vpc_id                     = aws_vpc.main.id
    private_subnet_ids         = join(",", aws_subnet.private[*].id)
    alb_dns_name               = aws_lb.internal.dns_name
    alb_listener_arn           = aws_lb_listener.http.arn
  }
}

resource "aws_ssm_parameter" "ephemeral" {
  for_each = local.ephemeral_parameters

  name      = "${local.ssm_prefix}/${each.key}"
  type      = "String"
  value     = each.value
  overwrite = true
}
