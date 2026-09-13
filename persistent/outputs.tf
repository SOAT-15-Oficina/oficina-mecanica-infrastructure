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
  description = <<-EOT
    Roles assumidas por OIDC, uma por repositorio. Cada uma vira o secret
    AWS_DEPLOY_ROLE_ARN do repositorio correspondente -- dentro do GitHub
    Environment deste ambiente (ver o output `deploy_contract`), nao no nivel do
    repositorio: os dois ambientes usam o mesmo nome de secret e so o escopo do
    Environment os separa.
  EOT
  value       = { for k, r in aws_iam_role.github : k => r.arn }
}

output "deploy_contract" {
  description = "Como o CI chega neste ambiente: branch, GitHub Environment e prefixo do SSM."
  value = {
    environment        = var.environment
    deploy_branch      = local.deploy_branch
    github_environment = local.github_environment
    ssm_prefix         = local.ssm_prefix
  }
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
  description = <<-EOT
    Identidades SES criadas por ESTA stack. Sao os REMETENTES verificados: a
    conta tem acesso de producao, entao a entrega nao se limita a esta lista.

    Vem vazio nos ambientes que nao as possuem (`manage_ses_identities = false`);
    eles enviam pelas identidades de producao, que sao da mesma conta.
  EOT
  value       = keys(aws_sesv2_email_identity.verified)
}

output "datadog" {
  description = <<-EOT
    Onde a observabilidade deste ambiente foi parar. `enabled = "false"` significa
    que a stack subiu sem Datadog -- nao que algo falhou.

    Os dois paineis abrem em https://app.<site>/dashboard/<id>.
  EOT

  value = {
    enabled               = local.datadog_enabled ? "true" : "false"
    site                  = local.datadog_enabled ? var.datadog_site : ""
    secret_arn            = local.datadog_enabled ? aws_secretsmanager_secret.datadog[0].arn : ""
    aws_integration       = local.manage_datadog_aws_integration ? aws_iam_role.datadog_integration[0].arn : "herdada do ambiente que a possui (ver manage_datadog_aws_integration)"
    forwarder_arn         = local.datadog_enabled && var.datadog_forward_cloudwatch_logs ? aws_cloudformation_stack.datadog_forwarder[0].outputs["DatadogForwarderArn"] : "desligado"
    dashboard_operacional = local.datadog_enabled ? datadog_dashboard.operational[0].id : ""
    dashboard_negocio     = local.datadog_enabled ? datadog_dashboard.business[0].id : ""
    synthetic_test_id     = local.datadog_enabled ? datadog_synthetics_test.ping[0].id : ""
    notification_targets  = join(" ", local.datadog_notification_targets)
  }
}
