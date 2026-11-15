output "public_base_url" {
  description = "URL publica da API (CloudFront + /api). O painel fica na raiz do mesmo dominio."
  value       = local.public_base_url
}

output "api_gateway_id" {
  description = "ID do HTTP API."
  value       = aws_apigatewayv2_api.main.id
}

output "frontend_bucket_name" {
  description = "Bucket do painel web."
  value       = aws_s3_bucket.frontend.id
}

output "jwt_secret_arn" {
  description = "Segredo compartilhado entre a Lambda de auth e os tres servicos."
  value       = aws_secretsmanager_secret.jwt.arn
}

output "internal_service_token_secret_arn" {
  description = "Token de servico que a Lambda envia em X-Service-Token e o OS Service confere."
  value       = aws_secretsmanager_secret.internal_service_token.arn
}

output "ses_verified_emails" {
  description = "Identidades SES lidas (nao criadas) por esta stack."
  value       = keys(data.aws_sesv2_email_identity.verified)
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
    dashboard_saga        = local.datadog_enabled ? datadog_dashboard.saga[0].id : ""
    logs_metrics          = local.manage_datadog_logs_metrics ? "declaradas por este ambiente" : "herdadas do ambiente que as possui (ver manage_datadog_logs_metrics)"
    synthetic_test_id     = nonsensitive(local.dd_synthetics_enabled ? datadog_synthetics_test.ping[0].id : "desligado")
    notification_targets  = join(" ", local.datadog_notification_targets)
  }
}

output "eks_cluster_name" {
  description = "Cluster onde os servicos rodam."
  value       = aws_eks_cluster.main.name
}

output "kubeconfig_command" {
  description = "Comando para apontar o kubectl ao cluster."
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${var.region}"
}

output "auth_lambda_name" {
  description = "Funcao de autenticacao. O pipeline do -serverless publica o codigo nela."
  value       = aws_lambda_function.auth.function_name
}

output "internal_alb_dns" {
  description = "DNS do ALB interno. So resolve de dentro da VPC."
  value       = aws_lb.internal.dns_name
}

output "alb_listener_arn" {
  description = "Listener do ALB interno. Cada servico pendura nele a propria regra de caminho."
  value       = aws_lb_listener.http.arn
}

output "mercadopago_webhook_url" {
  description = "URL a cadastrar no painel do Mercado Pago. Muda a cada bring-up, junto com o dominio do CloudFront."
  value       = "${local.public_base_url}/billing/webhooks/mercadopago"
}
