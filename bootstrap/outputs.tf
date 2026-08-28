output "state_bucket_name" {
  description = "Bucket a configurar no backend de persistent/ e ephemeral/."
  value       = aws_s3_bucket.state.id
}

output "state_lock_table_name" {
  description = "Tabela de lock a configurar no backend."
  value       = aws_dynamodb_table.state_lock.name
}
