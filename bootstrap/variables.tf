variable "region" {
  description = "Regiao AWS onde tudo e provisionado."
  type        = string
  default     = "sa-east-1"
}

variable "environment" {
  description = "Nome do ambiente. Prefixa recursos e parametros do SSM."
  type        = string
  default     = "prod"
}

variable "state_bucket_name" {
  description = "Bucket S3 do Terraform state. Nome precisa ser globalmente unico."
  type        = string
  default     = "oficina-mecanica-tfstate-881757053222"
}

variable "state_lock_table_name" {
  description = "Tabela DynamoDB usada para lock do state."
  type        = string
  default     = "oficina-mecanica-tflock"
}
