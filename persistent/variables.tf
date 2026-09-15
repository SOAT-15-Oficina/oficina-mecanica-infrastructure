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
    Enderecos de REMETENTE verificados no SES. A conta tem acesso de producao
    concedido, entao a entrega nao se limita a esta lista -- ela existe para os
    enderecos dos quais o sistema envia.

    A verificacao NAO e automatizavel -- cada endereco recebe um link que
    alguem precisa clicar. Por isso estas identidades vivem na camada
    persistente: destrui-las obrigaria a reverificar tudo antes de cada
    bring-up.
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

variable "datadog_enabled" {
  description = <<-EOT
    Se esta stack cria os recursos do Datadog: paineis, monitores, metricas de
    log, integracao com a AWS e o Forwarder.

    Com `false` nenhum deles e criado E o provider nem valida as credenciais --
    que e o que permite subir o ambiente inteiro sem conta no Datadog.

    CUIDADO ao passar de `true` para `false` num ambiente que ja aplicou: o
    proximo apply DESTROI paineis e monitores, junto com o historico de
    silenciamento deles.
  EOT
  type        = bool
  default     = true
}

variable "datadog_api_key" {
  description = <<-EOT
    Chave de API do Datadog (Organization Settings > API Keys).

    Vai para o Secrets Manager, de onde o agente do cluster e o Forwarder a
    leem. Nunca commitada: chega por TF_VAR_datadog_api_key, vinda de um secret
    do GitHub Environment.
  EOT
  type        = string
  default     = ""
  sensitive   = true
}

variable "datadog_app_key" {
  description = <<-EOT
    Chave de APLICACAO do Datadog (Organization Settings > Application Keys).

    E outra coisa que a chave de API: a de API autoriza ENVIAR dado, esta
    autoriza LER e ESCREVER configuracao -- painel, monitor, integracao. So o
    Terraform a usa; ela nao vai para dentro do cluster.
  EOT
  type        = string
  default     = ""
  sensitive   = true
}

variable "datadog_site" {
  description = <<-EOT
    Site da organizacao no Datadog. E a regiao onde a conta foi criada, visivel
    na URL do navegador -- `app.datadoghq.com` e `datadoghq.com`,
    `app.datadoghq.eu` e `datadoghq.eu`.

    Errar este valor NAO da erro de autenticacao obvio: o agente sobe, tenta
    enviar para o site errado e os paineis ficam vazios.
  EOT
  type        = string
  default     = "datadoghq.com"
}

variable "manage_datadog_aws_integration" {
  description = <<-EOT
    Se esta stack CRIA a integracao AWS <-> Datadog (a role de leitura e o
    vinculo com a conta).

    Mesmo problema das identidades do SES: a integracao pertence a CONTA, nao ao
    ambiente. Com dois ambientes na mesma conta, ambos criando-a, o segundo
    apply briga pelo mesmo recurso do lado do Datadog.

    Homologacao nao perde nada: as metricas da conta chegam com a tag `env` de
    cada recurso, entao os paineis dela filtram normalmente.

    Default: `true` em prod, `false` nos demais.
  EOT
  type        = bool
  default     = null
}

variable "manage_datadog_logs_metrics" {
  description = <<-EOT
    Se esta stack CRIA as metricas de log (`oficina.*`).

    Mesmo problema da integracao AWS, uma camada acima: o NOME de uma metrica de
    log e global na organizacao Datadog, nao por ambiente. Com os dois ambientes
    declarando `oficina.work_order_created`, o segundo apply recebe
    `409 Conflict: a metric already exists with that name`.

    Homologacao nao perde nada: a metrica e uma so, o filtro dela cobre os dois
    ambientes e o `group_by` em `env` separa o dado. Todo painel consulta
    `{$env}`, entao cada ambiente ve so o proprio numero.

    Default: `true` em prod, `false` nos demais.
  EOT
  type        = bool
  default     = null
}

variable "datadog_forward_cloudwatch_logs" {
  description = <<-EOT
    Se o Forwarder de logs do CloudWatch e criado e as assinaturas ligadas.

    E o que traz para o Datadog o access log do API Gateway e o log da Lambda --
    tudo que nasce FORA do cluster. Sem ele a correlacao de uma requisicao
    comeca dentro do pod, ja depois da borda, e o `request_id` da ADR-0011 perde
    metade da serventia.

    Desligue apenas para cortar custo de ingestao; e a primeira coisa a faltar
    quando alguem reclamar que "o trace para no meio".
  EOT
  type        = bool
  default     = true
}

variable "datadog_forwarder_template_url" {
  description = <<-EOT
    Template do CloudFormation do Datadog Forwarder.

    CONGELADO numa versao, de proposito. `latest.yaml` faz o proximo apply desta
    camada -- que roda a cada merge em main, e nao quando alguem decide atualizar
    o Forwarder -- trocar a versao da Lambda e da layer sem que nada no diff
    diga isso. Trocar de versao de coletor no meio de uma avaliacao e a forma
    mais barata de perder log sem explicacao.

    Para atualizar, mude este default num PR: o plano passa a mostrar a stack
    sendo alterada, que e exatamente o que se quer ver antes de trocar o
    coletor. Versoes: https://github.com/DataDog/datadog-serverless-functions/releases
  EOT
  type        = string
  default     = "https://datadog-cloudformation-template.s3.amazonaws.com/aws/forwarder/5.4.13.yaml"
}

variable "datadog_notification_targets" {
  description = <<-EOT
    Destinos dos alertas, na sintaxe de handle do Datadog: `@fulano@example.com`
    para e-mail, `@slack-canal` para Slack, `@pagerduty-servico` para PagerDuty.

    Vazio cai no remetente do SES (`ses_sender_email`), que ja e um e-mail que
    alguem do time le. Vazio E sem remetente do SES: o alerta dispara e fica so
    na interface do Datadog.
  EOT
  type        = list(string)
  default     = []
}

variable "datadog_alert_on_missing_agent" {
  description = <<-EOT
    Se o monitor "agente sem reportar" e criado.

    Desligado por padrao porque este ambiente sobe e desce por design: ele
    dispararia em todo tear-down. Ligue quando o ambiente ficar de pe de forma
    continua -- e o unico alerta que cobre o silencio dos outros.
  EOT
  type        = bool
  default     = false
}

variable "database_max_connections" {
  description = <<-EOT
    Teto de conexoes do RDS, usado como base do alerta em 80%.

    Nao e configurado em lugar nenhum: o Postgres no parameter group padrao usa
    `LEAST({DBInstanceClassMemory/9531392}, 5000)`, o que da ~112 numa
    db.t4g.micro (1 GiB). Trocar a classe da instancia (ephemeral/variables.tf)
    muda este numero -- e o alerta nao tem como descobrir sozinho.
  EOT
  type        = number
  default     = 112
}

variable "database_free_storage_alert_bytes" {
  description = <<-EOT
    Espaco livre minimo no RDS antes do alerta, em bytes.

    4 GiB = 20% dos 20 GB iniciais (ephemeral/rds.tf). O storage autoescala ate
    50 GB, entao este e um alerta de tendencia, nao de urgencia.
  EOT
  type        = number
  default     = 4294967296
}
