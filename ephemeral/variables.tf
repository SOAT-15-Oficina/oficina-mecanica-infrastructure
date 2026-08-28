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

variable "project" {
  description = "Prefixo comum de nomes de recurso."
  type        = string
  default     = "oficina-mecanica"
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "node_instance_type" {
  description = "Tipo das instancias do node group. On-demand por decisao do time."
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "Numero de nos. HPA vai de 2 a 10 replicas da API."
  type        = number
  default     = 2
}

variable "database_instance_class" {
  description = "Classe da instancia RDS."
  type        = string
  default     = "db.t4g.micro"
}

variable "api_replicas" {
  description = "Replicas iniciais da API. O HPA assume o controle depois."
  type        = number
  default     = 2
}

variable "kube_namespace" {
  description = "Namespace dos recursos da aplicacao."
  type        = string
  default     = "workshop"
}
