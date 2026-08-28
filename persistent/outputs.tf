output "public_base_url" {
  description = "URL publica do sistema. Painel na raiz, API sob /api."
  value       = "https://${aws_cloudfront_distribution.site.domain_name}"
}

output "api_gateway_id" {
  description = "ID do HTTP API. A camada efemera cria rotas e integracoes nele."
  value       = aws_apigatewayv2_api.main.id
}

output "ecr_repository_url" {
  description = "Repositorio de imagens do monolito."
  value       = aws_ecr_repository.api.repository_url
}

output "frontend_bucket_name" {
  description = "Bucket do painel web."
  value       = aws_s3_bucket.frontend.id
}

output "github_role_arns" {
  description = "Roles assumidas por OIDC. Configure cada uma como AWS_DEPLOY_ROLE_ARN no repositorio correspondente."
  value       = { for k, r in aws_iam_role.github : k => r.arn }
}

output "jwt_secret_arn" {
  description = "Segredo compartilhado entre a Lambda de auth e o monolito."
  value       = aws_secretsmanager_secret.jwt.arn
}

output "database_secret_arn" {
  description = "Credencial do RDS."
  value       = aws_secretsmanager_secret.database.arn
}

output "ses_verified_emails" {
  description = "Identidades SES. O SES esta em sandbox: so entrega para estas."
  value       = keys(aws_sesv2_email_identity.verified)
}
