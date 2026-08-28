resource "aws_db_subnet_group" "main" {
  name       = local.name
  subnet_ids = aws_subnet.private[*].id
}

# Postgres em subnets privadas, sem acesso publico. O schema e propriedade do
# oficina-mecanica-monolith: o Terraform entrega o banco VAZIO, e o Job de
# migration do pipeline daquele repositorio cria as tabelas e roda o seed.
#
# Faz parte da camada efemera por decisao do time: o ambiente inteiro sobe e
# desce a cada apresentacao, e migrations + seed rodam a cada bring-up.
resource "aws_db_instance" "main" {
  identifier = local.name
  engine     = "postgres"
  # Prefixo de familia, nao versao exata: `17.4` nao existe em sa-east-1 (a
  # familia comeca em 17.5) e minors sao descontinuadas com o tempo. Com
  # auto_minor_version_upgrade ligado, o provider aceita o prefixo e a AWS
  # resolve para a minor corrente.
  engine_version = "17"
  instance_class = var.database_instance_class

  allocated_storage     = 20
  max_allocated_storage = 50
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "techchallenge"
  username = local.database_credentials.username
  password = local.database_credentials.password
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false
  multi_az               = false

  # Ambiente efemero: sem estes tres, o tear-down trava.
  skip_final_snapshot     = true
  deletion_protection     = false
  backup_retention_period = 0

  apply_immediately          = true
  auto_minor_version_upgrade = false
}
