data "archive_file" "placeholder" {
  type        = "zip"
  source_file = "${path.module}/files/placeholder.py"
  output_path = "${path.module}/.terraform/placeholder.zip"
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "auth_lambda" {
  name               = "${local.name}-auth-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# Necessario para a funcao criar ENIs nas subnets privadas.
resource "aws_iam_role_policy_attachment" "auth_lambda_vpc" {
  role       = aws_iam_role.auth_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

data "aws_iam_policy_document" "auth_lambda" {
  statement {
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      data.aws_ssm_parameter.database_secret_arn.value,
      data.aws_ssm_parameter.jwt_secret_arn.value,
    ]
  }
}

resource "aws_iam_role_policy" "auth_lambda" {
  name   = "secrets"
  role   = aws_iam_role.auth_lambda.id
  policy = data.aws_iam_policy_document.auth_lambda.json
}

resource "aws_cloudwatch_log_group" "auth_lambda" {
  name              = "/aws/lambda/${local.name}-auth"
  retention_in_days = 7
}

# provided.al2023 + arm64 (Graviton): binario Go nativo, cold start de ~50-150ms
# fora o ENI da VPC na primeira invocacao.
#
# Nasce com um zip placeholder que responde 503. O artefato real e propriedade
# do pipeline do oficina-mecanica-serverless, que faz update-function-code --
# por isso o ignore_changes abaixo. Sem ele, todo apply desta camada reverteria
# a funcao para o placeholder.
resource "aws_lambda_function" "auth" {
  function_name = "${local.name}-auth"
  description   = "Autenticacao da plataforma: POST /auth/login e POST /auth/register"
  role          = aws_iam_role.auth_lambda.arn

  runtime       = "provided.al2023"
  architectures = ["arm64"]
  handler       = "bootstrap"

  filename         = data.archive_file.placeholder.output_path
  source_code_hash = data.archive_file.placeholder.output_base64sha256

  memory_size = 256
  timeout     = 15

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DATABASE_HOST      = aws_db_instance.main.address
      DATABASE_PORT      = tostring(aws_db_instance.main.port)
      DATABASE_NAME      = aws_db_instance.main.db_name
      DATABASE_SECRET_ID = data.aws_ssm_parameter.database_secret_arn.value
      JWT_SECRET_ID      = data.aws_ssm_parameter.jwt_secret_arn.value
    }
  }

  lifecycle {
    ignore_changes = [filename, source_code_hash, runtime, handler]
  }

  depends_on = [
    aws_iam_role_policy_attachment.auth_lambda_vpc,
    aws_cloudwatch_log_group.auth_lambda,
  ]
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auth.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${data.aws_ssm_parameter.api_gateway_execution_arn.value}/*/*"
}
