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

# IDs numericos usados pelo formato "immutable" do claim `sub` do GitHub OIDC.
#
# O GitHub passou a emitir o sub como
#   repo:<org>@<org_id>/<repo>@<repo_id>:<contexto>
# em vez do classico `repo:<org>/<repo>:<contexto>`. Os IDs sobrevivem a
# renomeacoes de org e de repositorio, que era o ponto da mudanca.
#
# Para reobte-los:
#   gh api orgs/<org> --jq .id
#   gh api repos/<org>/<repo> --jq .id
variable "github_org_id" {
  description = "ID numerico da organizacao GitHub."
  type        = number
  default     = 304170884
}

variable "github_repository_ids" {
  description = "ID numerico de cada repositorio, na mesma chave de local.repositories."
  type        = map(number)
  default = {
    infrastructure = 1349770613
    monolith       = 1349770766
    serverless     = 1349770930
    frontend       = 1349770282
  }
}
