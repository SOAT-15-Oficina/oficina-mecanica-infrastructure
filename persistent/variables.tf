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

# --- Diferencas entre ambientes ----------------------------------------------
#
# Os tres blocos abaixo aceitam `null` e caem num default derivado de
# `var.environment` (ver locals.tf). Assim o CI nao precisa passar TF_VAR_* extra
# para cada ambiente: basta `environment`, e a convencao main/prod e hml/homolog
# se aplica sozinha. Continuam sobrescritiveis para um ambiente que fuja dela.

variable "deploy_branch" {
  description = <<-EOT
    Branch cujos workflows podem assumir as roles deste ambiente. Entra na
    condicao `sub` da trust policy do OIDC.

    Default: `main` em prod, `hml` nos demais.
  EOT
  type        = string
  default     = null
}

variable "github_environment" {
  description = <<-EOT
    GitHub Environment usado pelos jobs de deploy deste ambiente. Entra na
    condicao `sub` da trust policy junto com a branch, e e onde vive o secret
    AWS_DEPLOY_ROLE_ARN correspondente.

    Default: `production` em prod, o proprio nome do ambiente nos demais.
  EOT
  type        = string
  default     = null
}

variable "manage_ses_identities" {
  description = <<-EOT
    Se esta stack CRIA as identidades verificadas do SES.

    Identidade SES pertence a CONTA, nao ao ambiente: e endereçada pelo proprio
    e-mail. Com dois ambientes na mesma conta, o segundo apply a criar o mesmo
    endereco morre com AlreadyExists.

    Por isso apenas UM ambiente as possui -- producao -- e os outros apenas
    enviam por elas (a policy IRSA da API usa `resources = ["*"]`, entao nao
    depende de posse). O que cada ambiente tem de proprio e o configuration set,
    que ja e nomeado por `local.name`.

    Default: `true` em prod, `false` nos demais.
  EOT
  type        = bool
  default     = null
}
