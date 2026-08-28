# Contrato entre os repositorios.
#
# Os pipelines de -monolith, -serverless e -frontend leem daqui os
# identificadores dos recursos que consomem. Nenhum deles precisa de Terraform
# instalado nem de acesso de leitura ao bucket de state (que contem segredos).
# Trocar um recurso de lugar nao vira PR em tres repositorios.
locals {
  persistent_parameters = {
    ecr_repository_url         = aws_ecr_repository.api.repository_url
    frontend_bucket_name       = aws_s3_bucket.frontend.id
    cloudfront_distribution_id = aws_cloudfront_distribution.site.id
    public_domain              = aws_cloudfront_distribution.site.domain_name
    public_base_url            = "https://${aws_cloudfront_distribution.site.domain_name}"
    api_gateway_id             = aws_apigatewayv2_api.main.id
    api_gateway_execution_arn  = aws_apigatewayv2_api.main.execution_arn
    api_gateway_endpoint       = aws_apigatewayv2_api.main.api_endpoint
    auth_lambda_name           = "${local.name}-auth"
    jwt_secret_arn             = aws_secretsmanager_secret.jwt.arn
    database_secret_arn        = aws_secretsmanager_secret.database.arn
    ses_configuration_set      = aws_sesv2_configuration_set.main.configuration_set_name
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
