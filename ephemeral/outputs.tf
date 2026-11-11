output "eks_cluster_name" {
  description = "Cluster onde os servicos rodam. Os pipelines deles usam em `aws eks update-kubeconfig`."
  value       = aws_eks_cluster.main.name
}

output "kubeconfig_command" {
  description = "Comando para apontar o kubectl ao cluster."
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${var.region}"
}

output "auth_lambda_name" {
  description = "Funcao de autenticacao. O pipeline do -serverless publica o codigo nela."
  value       = aws_lambda_function.auth.function_name
}

output "internal_alb_dns" {
  description = "DNS do ALB interno. So resolve de dentro da VPC, por design."
  value       = aws_lb.internal.dns_name
}

output "vpc_link_id" {
  description = "VPC Link que liga o API Gateway ao ALB interno."
  value       = aws_apigatewayv2_vpc_link.main.id
}

output "datadog_synthetic_test_id" {
  description = "Id do teste sintetico de /api/ping. Nasce e morre com o ambiente."
  value       = nonsensitive(local.dd_synthetics_enabled ? datadog_synthetics_test.ping[0].id : "desligado")
}

output "alb_listener_arn" {
  description = "Listener do ALB interno. Cada servico pendura nele a propria regra de caminho."
  value       = aws_lb_listener.http.arn
}

output "next_steps" {
  description = "O que falta para o ambiente ficar utilizavel."
  value       = <<-EOT
    A plataforma esta no ar, mas nenhum servico foi implantado ainda.

      1. -os-service:        infra/ (RDS, os-inbox, regra /*) e kustomize
      2. -billing-service:   infra/ (RDS, billing-inbox, regra /billing/*) e kustomize
      3. -execution-service: infra/ (DynamoDB, execution-inbox, regra /execution/*) e kustomize
      4. -serverless:        publica o codigo da Lambda
      5. -frontend:          s3 sync + invalidacao do CloudFront

    Ate o passo 1, o listener do ALB responde 404 para tudo que nao e /auth/*.
  EOT
}
