# Rotas, integracoes e VPC Link do API Gateway.
#
# O API em si e o stage vivem na camada PERSISTENTE, para o dominio
# {api_id}.execute-api... nao mudar entre ciclos e a origin do CloudFront
# continuar valida. O que depende da VPC -- e portanto e efemero -- e apenas o
# que esta neste arquivo. Com o ambiente desligado, o API existe e responde 404.
locals {
  api_id = data.aws_ssm_parameter.api_gateway_id.value
}

# O VPC Link cria ENIs nas subnets privadas para o API Gateway alcancar o ALB
# interno. E o que permite que NADA do EKS seja acessivel fora do gateway.
resource "aws_apigatewayv2_vpc_link" "main" {
  name               = local.name
  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.vpc_link.id]
}

# --- /auth/* -> Lambda --------------------------------------------------------

resource "aws_apigatewayv2_integration" "auth" {
  api_id                 = local.api_id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.auth.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "auth" {
  for_each = toset(["POST /auth/login", "POST /auth/register"])

  api_id    = local.api_id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.auth.id}"
}

# --- resto -> ALB interno -> pods ---------------------------------------------

resource "aws_apigatewayv2_integration" "api" {
  api_id             = local.api_id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = aws_lb_listener.http.arn
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.main.id
}

# Rota coringa: tudo que nao casa com uma rota explicita vai para o monolito.
# Como /auth/* e mais especifica, ela ganha.
resource "aws_apigatewayv2_route" "api_default" {
  api_id    = local.api_id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}
