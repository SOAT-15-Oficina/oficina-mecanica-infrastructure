locals {
  dd_rds_identifier   = local.name
  dd_lambda_name      = "${local.name}-auth"
  dd_api_id           = aws_apigatewayv2_api.main.id
  dd_kube_namespace   = "workshop"
  dd_dashboard_prefix = "${var.project} [${var.environment}]"
}
