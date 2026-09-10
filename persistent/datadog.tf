# Integracao com o Datadog -- a fundacao.
#
# Este arquivo cria o que precisa EXISTIR para haver observabilidade; os
# painieis, as metricas de log e os alertas estao nos arquivos irmaos
# datadog_metrics.tf, datadog_dashboard_*.tf e datadog_monitors.tf.
#
# POR QUE NA CAMADA PERSISTENTE. O ambiente sobe e desce (ver bring-up.yml).
# Painel e alerta que morressem no tear-down teriam de ser recriados a cada
# ciclo, e o historico de uma metrica so tem valor se atravessar os ciclos.
# Aqui eles sobrevivem: o que vive na camada efemera e apenas o AGENTE dentro do
# cluster (ephemeral/datadog.tf), que e descartavel por natureza.
#
# Ver docs/rfc/0004-estrategia-de-observabilidade.md.

locals {
  # Um unico interruptor. Com `false` nenhum recurso do Datadog e criado e o
  # provider nem sequer valida as credenciais -- util para quem sobe o ambiente
  # sem conta no Datadog.
  datadog_enabled = var.datadog_enabled

  # Identidade unificada (unified service tagging). Os mesmos tres valores
  # aparecem em metrica, log e trace, e sao o que permite pular de um para o
  # outro na interface.
  dd_env = var.environment

  dd_services = {
    api    = "monolith"
    lambda = "auth-lambda"
  }

  # Destinos de notificacao dos monitores. Sem nenhum, o alerta dispara e fica
  # so na interface -- e o remetente do SES ja e um e-mail que alguem do time le.
  datadog_notification_targets = length(var.datadog_notification_targets) > 0 ? var.datadog_notification_targets : (
    var.ses_sender_email != "" ? ["@${var.ses_sender_email}"] : []
  )

  dd_notify = join(" ", local.datadog_notification_targets)

  # Tags aplicadas a TODO monitor e painel. `env` casa com a tag que o agente
  # publica no cluster e com a tag das metricas vindas da AWS (ver o `env` em
  # local.common_tags), entao um filtro so atravessa as tres origens.
  dd_tags = [
    "env:${local.dd_env}",
    "project:${var.project}",
    "managed_by:terraform",
  ]

  # A integracao com a AWS e da CONTA, nao do ambiente -- mesmo problema das
  # identidades do SES (ver var.manage_ses_identities). Dois ambientes na mesma
  # conta criando a mesma integracao brigariam pelo mesmo recurso do lado do
  # Datadog. Producao a possui; homologacao apenas se beneficia dela, porque as
  # metricas chegam com a tag `env` de cada recurso.
  manage_datadog_aws_integration = local.datadog_enabled && (
    var.manage_datadog_aws_integration == null ? local.is_production : var.manage_datadog_aws_integration
  )

  # Conta da AWS de onde o Datadog assume a role de leitura. Valor fixo,
  # publicado por eles: https://docs.datadoghq.com/integrations/amazon_web_services/
  datadog_aws_principal = "464622532012"

  datadog_integration_role_name = "${local.name}-datadog-integration"
  datadog_forwarder_name        = "${local.name}-datadog-forwarder"
}

# --- Chave de API -------------------------------------------------------------
#
# Vive no Secrets Manager, e nao numa variavel do repositorio, por dois motivos:
# o agente dentro do cluster precisa le-la em tempo de execucao (a camada efemera
# a materializa como Secret do Kubernetes), e o Forwarder abaixo a le direto do
# ARN. O valor entra por TF_VAR_datadog_api_key, vindo de um secret do GitHub.
resource "aws_secretsmanager_secret" "datadog" {
  count = local.datadog_enabled ? 1 : 0

  name                    = "${local.name}/datadog-api-key"
  description             = "Chave de API do Datadog, lida pelo agente no cluster e pelo Forwarder"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "datadog" {
  count = local.datadog_enabled ? 1 : 0

  secret_id = aws_secretsmanager_secret.datadog[0].id

  # Texto puro, nao JSON: e o formato que o Forwarder do Datadog espera em
  # DdApiKeySecretArn ("You must store the secret as a plaintext").
  secret_string = var.datadog_api_key

  # Falha no PLANO, nao no apply pela metade. Sem a chave o agente sobe e nao
  # envia nada, e o sintoma (painel vazio) so aparece muito depois.
  lifecycle {
    precondition {
      condition     = var.datadog_api_key != ""
      error_message = "datadog_enabled = true exige TF_VAR_datadog_api_key. Para subir sem Datadog, passe TF_VAR_datadog_enabled=false."
    }
  }
}

# --- Integracao com a AWS -----------------------------------------------------
#
# Traz para o Datadog as metricas do CloudWatch dos servicos que o cluster NAO
# enxerga: API Gateway, Lambda, RDS, ALB e SES. Sem ela nao ha latencia de borda,
# duracao de Lambda nem conexao de banco.
#
# O `external_id` e emitido pelo Datadog e entra na trust policy da role: e o que
# impede um terceiro que descubra o ARN de assumi-la.
resource "datadog_integration_aws_external_id" "main" {
  count = local.manage_datadog_aws_integration ? 1 : 0
}

data "aws_iam_policy_document" "datadog_integration_assume_role" {
  count = local.manage_datadog_aws_integration ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.datadog_aws_principal}:root"]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [datadog_integration_aws_external_id.main[0].id]
    }
  }
}

resource "aws_iam_role" "datadog_integration" {
  count = local.manage_datadog_aws_integration ? 1 : 0

  name               = local.datadog_integration_role_name
  description        = "Leitura do CloudWatch e das tags, assumida pelo Datadog"
  assume_role_policy = data.aws_iam_policy_document.datadog_integration_assume_role[0].json
}

# So-leitura, e restrita ao que os paineis desta entrega consomem. A politica
# completa que o Datadog sugere cobre dezenas de servicos que este projeto nao
# usa -- nao ha razao para conceder o que nao sera lido.
data "aws_iam_policy_document" "datadog_integration" {
  count = local.manage_datadog_aws_integration ? 1 : 0

  statement {
    sid    = "ReadCloudWatch"
    effect = "Allow"
    actions = [
      "cloudwatch:Describe*",
      "cloudwatch:Get*",
      "cloudwatch:List*",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:DescribeSubscriptionFilters",
      "logs:FilterLogEvents",
      "logs:TestMetricFilter",
    ]
    resources = ["*"]
  }

  # As tags sao o que vira `env:prod` e `project:oficina-mecanica` do lado do
  # Datadog. Sem elas as metricas da AWS chegam sem como serem filtradas por
  # ambiente, e os dois ambientes da conta viram um so no painel.
  statement {
    sid    = "ReadTagsAndTopology"
    effect = "Allow"
    actions = [
      "tag:GetResources",
      "tag:GetTagKeys",
      "tag:GetTagValues",
      "apigateway:GET",
      "lambda:GetPolicy",
      "lambda:List*",
      "rds:Describe*",
      "rds:List*",
      "elasticloadbalancing:Describe*",
      "ec2:Describe*",
      "ses:Get*",
      "cloudfront:GetDistributionConfig",
      "cloudfront:ListDistributions",
      "support:DescribeTrustedAdvisorChecks",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "datadog_integration" {
  count = local.manage_datadog_aws_integration ? 1 : 0

  name   = "datadog-readonly"
  role   = aws_iam_role.datadog_integration[0].id
  policy = data.aws_iam_policy_document.datadog_integration[0].json
}

resource "datadog_integration_aws_account" "main" {
  count = local.manage_datadog_aws_integration ? 1 : 0

  aws_account_id = data.aws_caller_identity.current.account_id
  aws_partition  = "aws"

  auth_config {
    aws_auth_config_role {
      role_name   = aws_iam_role.datadog_integration[0].name
      external_id = datadog_integration_aws_external_id.main[0].id
    }
  }

  aws_regions {
    include_only = [var.region]
  }

  metrics_config {
    enabled = true

    # Sem filtro, o Datadog varre todo namespace do CloudWatch da conta -- que
    # hospeda outro projeto -- e cobra por metrica coletada. A lista e
    # exatamente o que os paineis leem.
    namespace_filters {
      include_only = [
        "AWS/ApiGateway",
        "AWS/ApplicationELB",
        "AWS/Lambda",
        "AWS/RDS",
        "AWS/SES",
        "AWS/CloudFront",
      ]
    }
  }

  logs_config {
    lambda_forwarder {
      # O Forwarder e declarado para o Datadog conseguir atribuir o log a esta
      # conta -- mas `sources` fica VAZIO de proposito.
      #
      # Preenchido, ele faria o Datadog assinar sozinho, do lado de la, os log
      # groups que ELE julgasse relevantes na conta -- que hospeda outro
      # projeto. Quais log groups sao encaminhados e decisao deste repositorio,
      # e aparece como `aws_cloudwatch_log_subscription_filter` no plano
      # (abaixo, e em ephemeral/datadog.tf para o log da Lambda).
      lambdas = var.datadog_forward_cloudwatch_logs ? [
        aws_cloudformation_stack.datadog_forwarder[0].outputs["DatadogForwarderArn"]
      ] : []

      sources = []
    }
  }

  # Os dois blocos abaixo sao obrigatorios pelo provider, e ambos ficam
  # desligados: X-Ray nao e usado (o traco vem do agente no cluster, ver
  # ephemeral/datadog.tf), e coleta estendida de recursos e postura de seguranca
  # sao produtos a parte, cobrados a parte, que nada nesta entrega consome.
  traces_config {
    xray_services {
      include_only = []
    }
  }

  resources_config {
    cloud_security_posture_management_collection = false
    extended_collection                          = false
  }
}

# --- Forwarder de logs do CloudWatch -----------------------------------------
#
# O agente do cluster cobre os pods. O que ele nao ve e o que nasce FORA do
# cluster: o access log do API Gateway -- onde vive o `requestId` que a
# aplicacao recebe como X-Request-Id (ADR-0011) -- e o log da Lambda de auth.
#
# Sao esses dois que fecham a correlacao ponta a ponta: sem eles o rastro de uma
# requisicao comeca dentro do pod, ja depois da borda.
#
# O Forwarder e distribuido pelo Datadog como template do CloudFormation. Nao ha
# equivalente em recurso nativo: e uma Lambda com layer, bucket de reprocesso e
# agendador. Mante-lo como stack do CloudFormation e mais honesto do que
# reimplementar tres dezenas de recursos e ter de segui-los a cada versao.
resource "aws_cloudformation_stack" "datadog_forwarder" {
  count = local.datadog_enabled && var.datadog_forward_cloudwatch_logs ? 1 : 0

  name = local.datadog_forwarder_name

  # AUTO_EXPAND por causa das macros do template; as duas de IAM porque ele cria
  # a role de execucao da Lambda com nome proprio.
  capabilities = ["CAPABILITY_IAM", "CAPABILITY_NAMED_IAM", "CAPABILITY_AUTO_EXPAND"]

  template_url = var.datadog_forwarder_template_url

  parameters = {
    DdApiKeySecretArn = aws_secretsmanager_secret.datadog[0].arn
    DdSite            = var.datadog_site
    FunctionName      = local.datadog_forwarder_name

    # As tags viajam com CADA log encaminhado. Sao elas que fazem o access log do
    # gateway cair no mesmo `env` das metricas do cluster.
    DdTags = join(",", [
      "env:${local.dd_env}",
      "project:${var.project}",
      "managed_by:terraform",
    ])

    # CPF e e-mail de cliente passam por rota e por corpo de requisicao. O
    # access log nao os registra hoje, mas o custo de deixar a rede ligada e
    # zero e o custo de descobrir tarde que vazou e alto.
    RedactEmail = "true"
    RedactIp    = "true"
  }

  # A stack e da conta, mas o nome carrega o ambiente: homologacao e producao
  # tem forwarders proprios, cada um etiquetando com o seu `env`.
  tags = local.common_tags
}

# O access log do API Gateway e da camada PERSISTENTE (persistent/apigateway.tf),
# entao a assinatura dele tambem e. O log da Lambda de auth e efemero e sua
# assinatura vive em ephemeral/datadog.tf.
resource "aws_cloudwatch_log_subscription_filter" "api_access" {
  count = local.datadog_enabled && var.datadog_forward_cloudwatch_logs ? 1 : 0

  name            = "datadog"
  log_group_name  = aws_cloudwatch_log_group.api_access.name
  destination_arn = aws_cloudformation_stack.datadog_forwarder[0].outputs["DatadogForwarderArn"]

  # Vazio: todo evento do access log interessa. E JSON estruturado desde a
  # origem (ver o `format` do access_log_settings), nao texto para filtrar.
  filter_pattern = ""
}

# --- Contrato com as outras camadas e repositorios ----------------------------
#
# Mesmo mecanismo do resto: quem consome le do SSM e nao precisa do state.
#
# Os quatro parametros existem SEMPRE, inclusive com o Datadog desligado, e os
# ausentes viram o marcador "unset" -- mesma convencao de `ses_sender_email`.
# A alternativa (publicar so quando ligado) obrigaria a camada efemera a
# adivinhar quais parametros existem, e `data` source nao aceita `count`.
locals {
  datadog_forwarder_arn = local.datadog_enabled && var.datadog_forward_cloudwatch_logs ? (
    aws_cloudformation_stack.datadog_forwarder[0].outputs["DatadogForwarderArn"]
  ) : "unset"

  datadog_parameters = {
    datadog_enabled       = local.datadog_enabled ? "true" : "false"
    datadog_site          = var.datadog_site
    datadog_secret_arn    = local.datadog_enabled ? aws_secretsmanager_secret.datadog[0].arn : "unset"
    datadog_forwarder_arn = local.datadog_forwarder_arn
  }
}

resource "aws_ssm_parameter" "datadog" {
  for_each = local.datadog_parameters

  name  = "${local.ssm_prefix}/${each.key}"
  type  = "String"
  value = each.value
}
