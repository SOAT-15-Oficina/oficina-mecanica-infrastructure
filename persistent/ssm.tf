# Contrato entre os repositorios.
#
# Os pipelines dos servicos, do -serverless e do -frontend leem daqui os
# identificadores dos recursos que consomem. Nenhum deles precisa de Terraform
# instalado nem de acesso de leitura ao bucket de state (que contem segredos).
# Trocar um recurso de lugar nao vira PR em tres repositorios.
locals {
  persistent_parameters = {
    frontend_bucket_name              = aws_s3_bucket.frontend.id
    cloudfront_distribution_id        = aws_cloudfront_distribution.site.id
    public_domain                     = aws_cloudfront_distribution.site.domain_name
    public_base_url                   = "https://${aws_cloudfront_distribution.site.domain_name}/api"
    api_gateway_id                    = aws_apigatewayv2_api.main.id
    api_gateway_execution_arn         = aws_apigatewayv2_api.main.execution_arn
    api_gateway_endpoint              = aws_apigatewayv2_api.main.api_endpoint
    auth_lambda_name                  = "${local.name}-auth"
    jwt_secret_arn                    = aws_secretsmanager_secret.jwt.arn
    internal_service_token_secret_arn = aws_secretsmanager_secret.internal_service_token.arn
    ses_configuration_set             = aws_sesv2_configuration_set.main.configuration_set_name
    # Pode estar vazio antes de alguem verificar o remetente no SES, e o SSM
    # recusa valor vazio -- guarda um marcador explicito.
    ses_sender_email = coalesce(var.ses_sender_email, "unset")
  }
}

resource "aws_ssm_parameter" "persistent" {
  for_each = local.persistent_parameters

  name  = "${local.ssm_prefix}/${each.key}"
  type  = "String"
  value = each.value
}
