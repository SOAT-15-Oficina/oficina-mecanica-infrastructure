# ALB INTERNO criado pelo Terraform -- nao por um Ingress.
#
# Motivo: a integracao VPC Link do HTTP API aponta para o ARN de um LISTENER.
# Se o ALB nascesse de um Ingress, quem o criaria seria o AWS Load Balancer
# Controller, de forma assincrona, e o ARN nao existiria no momento do plan --
# obrigando a descoberta por tag com retry ou a um apply em duas fases.
#
# Como consequencia util, o Terraform passa a ser dono do ALB: o destroy remove
# na ordem certa e o problema classico de ENI orfa travando a delecao da subnet
# deixa de existir. O controller entra apenas pelo CR TargetGroupBinding, para
# manter o target group populado com os IPs dos pods (ver k8s.tf).
resource "aws_lb" "internal" {
  name               = substr("${local.name}-int", 0, 32)
  internal           = true
  load_balancer_type = "application"
  subnets            = aws_subnet.private[*].id
  security_groups    = [aws_security_group.alb.id]

  # Ambiente efemero: nao ha o que proteger de um destroy acidental, e a
  # protecao so atrapalharia o tear-down.
  enable_deletion_protection = false
}

resource "aws_lb_target_group" "api" {
  name        = substr("${local.name}-api", 0, 32)
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/ready"
    protocol            = "HTTP"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }

  # Enquanto o Deployment estiver com a imagem placeholder, nenhum target fica
  # saudavel -- e esperado ate o primeiro deploy do -monolith.
  deregistration_delay = 15
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}
