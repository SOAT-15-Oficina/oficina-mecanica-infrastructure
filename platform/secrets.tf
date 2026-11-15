resource "random_password" "jwt" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "jwt" {
  name                    = "${local.name}/jwt-secret"
  description             = "Chave HS256 compartilhada entre a Lambda de auth e os servicos"
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
