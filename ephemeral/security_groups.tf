resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "ALB interno; recebe trafego apenas do VPC Link do API Gateway"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-alb" }
}

resource "aws_security_group" "vpc_link" {
  name        = "${local.name}-vpc-link"
  description = "ENIs do VPC Link do API Gateway"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-vpc-link" }
}

resource "aws_security_group" "nodes" {
  name        = "${local.name}-nodes"
  description = "Nos do EKS"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-nodes" }
}

resource "aws_security_group" "lambda" {
  name        = "${local.name}-lambda"
  description = "Funcao de autenticacao, em subnets privadas"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-lambda" }
}

resource "aws_security_group" "database" {
  name        = "${local.name}-database"
  description = "RDS; aceita apenas nos do EKS e a Lambda de autenticacao"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-database" }
}

# --- ALB: so o VPC Link entra; so os nos saem ------------------------------

resource "aws_vpc_security_group_ingress_rule" "alb_from_vpc_link" {
  security_group_id            = aws_security_group.alb.id
  description                  = "API Gateway via VPC Link"
  referenced_security_group_id = aws_security_group.vpc_link.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_to_nodes" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Pods da API"
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}

resource "aws_vpc_security_group_egress_rule" "vpc_link_to_alb" {
  security_group_id            = aws_security_group.vpc_link.id
  description                  = "ALB interno"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

# --- Nos ---------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "nodes_from_alb" {
  security_group_id            = aws_security_group.nodes.id
  description                  = "ALB interno"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}

resource "aws_vpc_security_group_ingress_rule" "nodes_self" {
  security_group_id            = aws_security_group.nodes.id
  description                  = "Trafego entre pods"
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "-1"
}

# Saida ampla: os nos precisam de ECR, SES, Secrets Manager, do control plane do
# EKS e das imagens em registries publicos.
resource "aws_vpc_security_group_egress_rule" "nodes_all" {
  security_group_id = aws_security_group.nodes.id
  description       = "Saida pelo NAT"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# --- Lambda ------------------------------------------------------------------

resource "aws_vpc_security_group_egress_rule" "lambda_all" {
  security_group_id = aws_security_group.lambda.id
  description       = "RDS e Secrets Manager"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# --- RDS: nunca exposto -------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "database_from_nodes" {
  security_group_id            = aws_security_group.database.id
  description                  = "Pods da API"
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_vpc_security_group_ingress_rule" "database_from_lambda" {
  security_group_id            = aws_security_group.database.id
  description                  = "Funcao de autenticacao"
  referenced_security_group_id = aws_security_group.lambda.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
