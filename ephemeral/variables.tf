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

variable "datadog_chart_version" {
  description = <<-EOT
    Versao do chart `datadog/datadog` (o agente dentro do cluster).

    Pinada, e nao `latest`: o chart publica varias versoes por semana, e um
    bring-up que instalasse a mais nova faria de cada ciclo um upgrade nao
    revisado do agente.

    Se ha ou nao Datadog neste ambiente NAO se decide aqui -- vem do SSM, que a
    camada persistente publica (ver ephemeral/datadog.tf).
  EOT
  type        = string
  default     = "3.244.0"
}

# As duas chaves abaixo existem porque o teste sintetico passou a ser desta
# camada. O agente dentro do cluster nao usa nenhuma das duas: ele le a API key
# do Secrets Manager, cujo ARN vem do SSM.
variable "datadog_api_key" {
  description = "API key do Datadog. Vem de TF_VAR_datadog_api_key nos workflows."
  type        = string
  default     = ""
  sensitive   = true
}

variable "datadog_app_key" {
  description = <<-EOT
    Application key do Datadog, exigida para criar teste sintetico.

    Vazia desliga o teste (`local.dd_synthetics_enabled`), o que mantem
    `terraform validate` e um apply local funcionando sem credencial de Datadog.
  EOT
  type        = string
  default     = ""
  sensitive   = true
}
