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

variable "project" {
  description = "Prefixo comum de nomes de recurso."
  type        = string
  default     = "oficina-mecanica"
}

variable "github_org" {
  description = "Organizacao GitHub dona dos repositorios."
  type        = string
  default     = "SOAT-15-Oficina"
}

variable "github_org_id" {
  description = "ID numerico da organizacao GitHub (gh api orgs/<org> --jq .id)."
  type        = number
  default     = 304170884
}

variable "github_repository_ids" {
  description = "ID numerico de cada repositorio, na mesma chave de local.repositories. Repositorio sem ID confia so no formato classico do sub."
  type        = map(number)
  default = {
    infrastructure      = 1349770613
    "os-service"        = 1349770766
    "billing-service"   = 1458438521
    "execution-service" = 1458438553
    serverless          = 1349770930
    frontend            = 1349770282
  }
}

variable "deploy_environments" {
  description = "Ambientes com roles de deploy: branch e GitHub Environment aceitos na trust policy de cada um."
  type = map(object({
    branch             = string
    github_environment = string
  }))
  default = {
    homolog = { branch = "hml", github_environment = "homolog" }
    prod    = { branch = "main", github_environment = "production" }
  }
}
