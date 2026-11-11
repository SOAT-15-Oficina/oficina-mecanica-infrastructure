# Segredos na camada persistente para nao mudarem a cada bring-up: se fossem
# recriados junto com o RDS, todo token emitido antes deixaria de valer e o
# ambiente local precisaria ser reconfigurado a cada ciclo.

resource "random_password" "jwt" {
  length  = 64
  special = false
}

# Assinado pela Lambda (oficina-mecanica-serverless), validado pelo monolito.
# Um segredo, dois leitores.
resource "aws_secretsmanager_secret" "jwt" {
  name                    = "${local.name}/jwt-secret"
  description             = "Chave HS256 compartilhada entre a Lambda de auth e o monolito"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "jwt" {
  secret_id     = aws_secretsmanager_secret.jwt.id
  secret_string = random_password.jwt.result
}

resource "random_password" "internal_service_token" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "internal_service_token" {
  name                    = "${var.project}/${var.environment}/internal-service-token"
  description             = "Token de servico entre a Lambda de auth e as rotas /internal do OS Service"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "internal_service_token" {
  secret_id     = aws_secretsmanager_secret.internal_service_token.id
  secret_string = random_password.internal_service_token.result
}
