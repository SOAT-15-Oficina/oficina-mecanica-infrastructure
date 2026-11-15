locals {
  dd_rds_identifier   = "oficina-${var.environment}-*"
  dd_lambda_name      = "${local.name}-auth"
  dd_api_id           = aws_apigatewayv2_api.main.id
  dd_kube_namespace   = var.kube_namespace
  dd_queue_prefix     = "oficina-${var.environment}"
  dd_dashboard_prefix = "${var.project} [${var.environment}]"
}
