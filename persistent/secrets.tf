# Segredos na camada persistente para nao mudarem a cada bring-up: se fossem
# recriados junto com o RDS, todo token emitido antes deixaria de valer e o
# ambiente local precisaria ser reconfigurado a cada ciclo.

resource "random_password" "jwt" {
  length  = 64
  special = false
}

resource "random_password" "database" {
  length  = 32
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

# Formato consumido por internal/config do -serverless: {"username","password"}.
resource "aws_secretsmanager_secret" "database" {
  name                    = "${local.name}/database"
  description             = "Credencial do RDS, lida pela Lambda e materializada no cluster"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "database" {
  secret_id = aws_secretsmanager_secret.database.id

  secret_string = jsonencode({
    username = "techchallenge"
    password = random_password.database.result
  })
}
