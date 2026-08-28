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

variable "github_org" {
  description = "Organizacao GitHub dona dos quatro repositorios."
  type        = string
  default     = "SOAT-15-Oficina"
}

variable "ses_verified_emails" {
  description = <<-EOT
    Enderecos verificados no SES. O SES opera em sandbox: so entrega para
    enderecos desta lista, com teto de 200 e-mails/24h.

    A verificacao NAO e automatizavel -- cada endereco recebe um link que
    alguem precisa clicar. Por isso estas identidades vivem na camada
    persistente: destrui-las obrigaria a reverificar tudo antes de cada
    apresentacao.
  EOT
  type        = list(string)
  default     = []
}

variable "ses_sender_email" {
  description = "Remetente dos e-mails de orcamento. Precisa estar verificado."
  type        = string
  default     = ""
}
