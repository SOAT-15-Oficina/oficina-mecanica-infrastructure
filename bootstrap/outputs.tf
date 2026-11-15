output "state_bucket_name" {
  description = "Bucket a configurar no backend de platform/ e do infra/ dos servicos."
  value       = aws_s3_bucket.state.id
}

output "state_lock_table_name" {
  description = "Tabela de lock a configurar no backend."
  value       = aws_dynamodb_table.state_lock.name
}

output "github_role_arns" {
  description = "Role de deploy de cada repositorio, por ambiente. Cada ARN vira o secret AWS_DEPLOY_ROLE_ARN do GitHub Environment correspondente."
  value = {
    for env in keys(var.deploy_environments) : env => {
      for key, role in local.deploy_roles : role.repo => aws_iam_role.github[key].arn
      if role.environment == env
    }
  }
}
