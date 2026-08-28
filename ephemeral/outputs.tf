output "eks_cluster_name" {
  description = "Cluster onde a API roda. O pipeline do -monolith usa em `aws eks update-kubeconfig`."
  value       = aws_eks_cluster.main.name
}

output "kubeconfig_command" {
  description = "Comando para apontar o kubectl ao cluster."
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${var.region}"
}

output "database_endpoint" {
  description = "Endpoint do RDS. Privado: alcancavel apenas de dentro da VPC."
  value       = aws_db_instance.main.address
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

output "next_steps" {
  description = "O que falta para o ambiente ficar utilizavel."
  value       = <<-EOT
    O ambiente esta provisionado, mas ainda serve placeholders.

      1. -monolith:   push em main -> imagem no ECR, Job de migration, rollout
      2. -serverless: push em main -> publica o codigo da Lambda
      3. -frontend:   push em main -> s3 sync + invalidacao do CloudFront

    Ate o passo 1, o Deployment roda registry.k8s.io/pause e nenhum target do
    ALB fica saudavel -- isso e esperado.
  EOT
}
