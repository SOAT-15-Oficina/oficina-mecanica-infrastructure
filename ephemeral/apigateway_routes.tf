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

  # Sem `request_parameters` aqui: parameter mapping so existe em integracao
  # HTTP_PROXY. A Lambda nao precisa dele -- ela le o mesmo identificador em
  # RequestContext.RequestID, que E o `$context.requestId` do access log
  # (ADR-0011, secao 5).
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

  # O ELO QUE FECHA A CORRELACAO BORDA <-> APLICACAO (ADR-0011).
  #
  # `$context.requestId` e o mesmo identificador que o access log do gateway
  # registra (ver o `format` do access_log_settings em persistent/apigateway.tf).
  # Injetado como header, ele chega ao monolito, que o adota como `request_id` de
  # toda linha de log da requisicao. Uma consulta por esse valor no Datadog passa
  # a devolver o rastro inteiro: access log da borda + linhas de dentro do pod.
  #
  # Sem isto, o middleware da aplicacao geraria um UUID proprio a cada
  # requisicao -- os dois lados continuariam existindo, mas sem nada em comum
  # para juntar um ao outro.
  #
  # `append:` e nao `overwrite:`: se o cliente mandou um X-Request-Id, ele
  # continua visivel, e o valor do gateway entra ao final da lista. A aplicacao
  # fica com o ULTIMO, que e o unico que ela sabe ter nascido na borda -- header
  # de cliente e entrada nao confiavel e nao pode virar chave de correlacao.
  request_parameters = {
    "append:header.x-request-id" = "$context.requestId"
  }
}

# Rota coringa: tudo que nao casa com uma rota explicita vai para o monolito.
# Como /auth/* e mais especifica, ela ganha.
resource "aws_apigatewayv2_route" "api_default" {
  api_id    = local.api_id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}
