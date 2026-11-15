locals {
  platform_parameters = {
    frontend_bucket_name              = aws_s3_bucket.frontend.id
    cloudfront_distribution_id        = aws_cloudfront_distribution.site.id
    public_domain                     = aws_cloudfront_distribution.site.domain_name
    public_base_url                   = local.public_base_url
    api_gateway_id                    = aws_apigatewayv2_api.main.id
    api_gateway_execution_arn         = aws_apigatewayv2_api.main.execution_arn
    api_gateway_endpoint              = aws_apigatewayv2_api.main.api_endpoint
    auth_lambda_name                  = aws_lambda_function.auth.function_name
    jwt_secret_arn                    = aws_secretsmanager_secret.jwt.arn
    internal_service_token_secret_arn = aws_secretsmanager_secret.internal_service_token.arn
    ses_configuration_set             = aws_sesv2_configuration_set.main.configuration_set_name
    ses_sender_email                  = coalesce(var.ses_sender_email, "unset")
    eks_cluster_name                  = aws_eks_cluster.main.name
    eks_cluster_endpoint              = aws_eks_cluster.main.endpoint
    eks_oidc_provider_arn             = aws_iam_openid_connect_provider.cluster.arn
    eks_node_security_group_id        = local.node_security_group_id
    kube_namespace                    = kubernetes_namespace.workshop.metadata[0].name
    vpc_id                            = aws_vpc.main.id
    private_subnet_ids                = join(",", aws_subnet.private[*].id)
    alb_dns_name                      = aws_lb.internal.dns_name
    alb_listener_arn                  = aws_lb_listener.http.arn
  }

  public_base_url = "https://${aws_cloudfront_distribution.site.domain_name}/api"
}

resource "aws_ssm_parameter" "platform" {
  for_each = merge(local.platform_parameters, local.datadog_parameters)

  name  = "${local.ssm_prefix}/${each.key}"
  type  = "String"
  value = each.value
}
