# API Gateway HTTP API -- a UNICA porta de entrada do sistema.
#
# Vive na camada persistente por dois motivos:
#
#   1. Custa US$ 0 parado (cobranca e por requisicao, 1M/mes no free tier).
#   2. O CloudFront tambem e persistente, e a origin dele e o dominio
#      {api_id}.execute-api... Se o API fosse recriado a cada bring-up, o
#      dominio mudaria e a origin do CloudFront ficaria apontando para o vazio.
#
# As ROTAS, INTEGRACOES e o VPC LINK vivem na camada efemera, porque dependem da
# VPC, do ALB e da Lambda. Enquanto o ambiente esta desligado, este API existe e
# responde 404 -- que e o comportamento correto.
resource "aws_apigatewayv2_api" "main" {
  name          = "${local.name}-api"
  protocol_type = "HTTP"
  description   = "Porta unica: /auth/* na Lambda, o resto no ALB interno do EKS"
}

# Stage $default: sem prefixo de stage na URL, entao o caminho que o CloudFront
# encaminha chega inalterado.
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 200
    throttling_rate_limit  = 100
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      httpMethod     = "$context.httpMethod"
      path           = "$context.path"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      integrationErr = "$context.integrationErrorMessage"
    })
  }

  # As rotas sao criadas e destruidas pela camada efemera. Sem isto, todo apply
  # da camada persistente tentaria reverter o que a efemera acabou de criar.
  lifecycle {
    ignore_changes = [default_route_settings]
  }
}

resource "aws_cloudwatch_log_group" "api_access" {
  name              = "/aws/apigateway/${local.name}"
  retention_in_days = 7
}
