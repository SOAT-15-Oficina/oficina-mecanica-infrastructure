# O agente do Datadog dentro do cluster.
#
# DIVISAO DE TRABALHO COM A CAMADA PERSISTENTE. La ficam painel, monitor,
# metrica de log, integracao com a AWS e o Forwarder -- tudo que precisa
# sobreviver ao tear-down. Aqui fica so o COLETOR, que e descartavel: ele nasce
# com o cluster, e um cluster novo e descoberto sozinho pelo autodiscovery.
#
# O que este agente cobre e o que a integracao AWS nao alcanca: metrica de
# container (cAdvisor), estado de objeto do Kubernetes (kube-state-metrics), log
# de pod e traco de APM.
#
# Ver docs/rfc/0004-estrategia-de-observabilidade.md.

# A camada persistente publica no SSM se ha Datadog neste ambiente e onde estao
# as pecas dele. Ler dali, em vez de repetir a variavel aqui, evita o estado
# impossivel em que uma camada acha que ha Datadog e a outra acha que nao.
#
# Os quatro parametros existem sempre; os ausentes valem "unset" -- por isso
# nenhum destes `data` precisa de condicional, que `data` source nao aceita.
data "aws_ssm_parameter" "datadog_enabled" {
  name = "${local.ssm_prefix}/datadog_enabled"
}

data "aws_ssm_parameter" "datadog_site" {
  name = "${local.ssm_prefix}/datadog_site"
}

data "aws_ssm_parameter" "datadog_secret_arn" {
  name = "${local.ssm_prefix}/datadog_secret_arn"
}

data "aws_ssm_parameter" "datadog_forwarder_arn" {
  name = "${local.ssm_prefix}/datadog_forwarder_arn"
}

locals {
  # `nonsensitive` porque o provider marca TODO valor de SSM como sensivel, sem
  # olhar o conteudo -- e um `count` nao aceita valor sensivel. Nenhum destes
  # quatro e segredo: sao um booleano, um dominio e dois ARNs. A chave de API,
  # essa sim, continua vindo do Secrets Manager e continua sensivel.
  datadog_enabled = nonsensitive(data.aws_ssm_parameter.datadog_enabled.value) == "true"
  datadog_site    = nonsensitive(data.aws_ssm_parameter.datadog_site.value)

  datadog_secret_arn = nonsensitive(data.aws_ssm_parameter.datadog_secret_arn.value)

  # "unset" quando a camada persistente subiu com o encaminhamento desligado.
  datadog_forwarder_arn = nonsensitive(data.aws_ssm_parameter.datadog_forwarder_arn.value)

  datadog_secret_name = "datadog-api-key"

  # Unified service tagging: os mesmos valores em metrica, log e traco.
  # `version` fica de fora de proposito -- ela e a tag da imagem, que pertence
  # ao pipeline do -monolith (ver o ignore_changes do Deployment).
  dd_env     = var.environment
  dd_service = "monolith"

  # O nome de servico da Lambda de auth (ephemeral/lambda.tf a injeta como
  # DD_SERVICE). Nome proprio, e nao "monolith": e por `@service` que os paineis
  # e as metricas de log separam as duas origens.
  dd_service_lambda = "auth-lambda"
}

# Rotulos e anotacoes que o Deployment da API (k8s.tf) aplica no template do
# pod. Ficam aqui, e nao la, porque sao parte do desenho de observabilidade e
# desaparecem inteiros quando `datadog_enabled` e falso.
locals {
  # `tags.datadoghq.com/*` e a convencao que o agente le para preencher as tags
  # `env` e `service` das metricas do container. Sem elas, o pod aparece nos
  # paineis identificado apenas por nome de container.
  datadog_pod_labels = local.datadog_enabled ? {
    "tags.datadoghq.com/env"     = local.dd_env
    "tags.datadoghq.com/service" = local.dd_service
  } : {}

  # Autodiscovery: diz ao agente COMO tratar o log deste container em vez de o
  # deixar adivinhar. `source: go` seleciona o pipeline de parsing certo -- e o
  # que faz `@request_id` e `@event` virarem facets consultaveis, em vez de
  # texto dentro de uma mensagem.
  #
  # A chave carrega o nome do container ("api"), nao o do pod: e por container
  # que o autodiscovery casa.
  datadog_pod_annotations = local.datadog_enabled ? {
    "ad.datadoghq.com/api.logs" = jsonencode([
      {
        source  = "go"
        service = local.dd_service
      },
    ])
  } : {}
}

data "aws_secretsmanager_secret_version" "datadog" {
  count = local.datadog_enabled ? 1 : 0

  secret_id = local.datadog_secret_arn
}

# O chart le a chave de um Secret existente em vez de recebe-la por `set`: valor
# passado por `set` aparece em texto claro no release do Helm, que qualquer um
# com acesso ao namespace consegue ler.
resource "kubernetes_secret" "datadog" {
  count = local.datadog_enabled ? 1 : 0

  metadata {
    name      = local.datadog_secret_name
    namespace = "kube-system"
  }

  data = {
    "api-key" = data.aws_secretsmanager_secret_version.datadog[0].secret_string
  }

  type = "Opaque"
}

resource "helm_release" "datadog" {
  count = local.datadog_enabled ? 1 : 0

  name       = "datadog"
  repository = "https://helm.datadoghq.com"
  chart      = "datadog"
  version    = var.datadog_chart_version
  namespace  = "kube-system"

  # Um YAML so, e nao uma pilha de blocos `set`: metade destes valores sao
  # aninhados em tres niveis, e `set` com chave escapada e ilegivel depois do
  # segundo ponto.
  values = [yamlencode({
    datadog = {
      site        = local.datadog_site
      clusterName = aws_eks_cluster.main.name

      apiKeyExistingSecret = local.datadog_secret_name

      # As tags que atravessam metrica, log e traco. Sao as mesmas que a
      # integracao AWS traz nos recursos (ver o `env` em local.common_tags), e e
      # isso que faz um filtro por `env` funcionar nas duas origens ao mesmo
      # tempo.
      tags = [
        "env:${local.dd_env}",
        "project:${var.project}",
        "managed_by:terraform",
      ]

      env = [
        { name = "DD_ENV", value = local.dd_env },
      ]

      logs = {
        enabled = true

        # Coleta de TUDO que roda no cluster, e nao so do que tiver anotacao.
        # Num cluster deste tamanho o volume e baixo, e o log que falta e
        # sempre o do container em que ninguem pensou em por a anotacao.
        containerCollectAll = true

        # Sem isto, um pod que reinicia perde o log do que aconteceu antes de
        # cair -- justamente o que se quer ler.
        containerCollectUsingFiles = true
      }

      apm = {
        # Os dois caminhos ligados: o socket de dominio Unix e o preferido (nao
        # expoe o agente na rede do no), e a porta TCP e o que o dd-trace-go usa
        # quando recebe DD_AGENT_HOST -- que e o caso aqui, ver k8s.tf.
        portEnabled   = true
        socketEnabled = true
      }

      processAgent = {
        enabled           = true
        processCollection = false
      }

      kubeStateMetricsCore = {
        # Fonte de kubernetes_state.hpa.*, kubernetes_state.pod.status_phase e
        # kubernetes_state.container.restarts -- as tres metricas que os
        # paineis e os alertas de cluster consultam.
        enabled = true
      }

      # O `kubeStateMetricsCore` acima ja coleta o mesmo dado, dentro do cluster
      # agent. Deixar `true` aqui subiria TAMBEM o Deployment avulso do
      # kube-state-metrics como subchart -- as mesmas series, coletadas duas
      # vezes, cobradas duas vezes.
      kubeStateMetricsEnabled = false

      clusterChecks = {
        enabled = true
      }
    }

    clusterAgent = {
      enabled  = true
      replicas = 1

      metricsProvider = {
        # DESLIGADO de proposito. Ligado, o cluster agent registra
        # external.metrics.k8s.io e passa a servir metricas para HPA -- coisa
        # que o HPA daqui nao pede (ele usa CPU e memoria do metrics-server).
        enabled = false
      }
    }

    agents = {
      # DaemonSet: um agente por no, coletando os pods daquele no.
      enabled = true

      containers = {
        agent = {
          resources = {
            requests = { cpu = "100m", memory = "256Mi" }
            limits   = { cpu = "400m", memory = "512Mi" }
          }
        }
      }

      tolerations = [
        {
          operator = "Exists"
        },
      ]
    }
  })]

  # O node group precisa existir (nao ha onde agendar um DaemonSet sem no), e o
  # Secret com a chave precisa existir antes do pod tentar monta-lo.
  depends_on = [
    aws_eks_node_group.main,
    kubernetes_secret.datadog,
  ]
}

# --- Log da Lambda de autenticacao -------------------------------------------
#
# O par da assinatura que a camada persistente faz no access log do API Gateway.
# Os dois log groups juntos fecham o rastro da borda: o gateway registra o
# `requestId`, a Lambda registra o mesmo valor como `request_id` (ADR-0011), e o
# monolito o recebe como header X-Request-Id.
#
# O log group e efemero (nasce e morre com a funcao), entao a assinatura mora
# aqui; o Forwarder que a recebe e persistente e vem pelo SSM.
resource "aws_cloudwatch_log_subscription_filter" "auth_lambda" {
  count = local.datadog_enabled && local.datadog_forwarder_arn != "unset" ? 1 : 0

  name            = "datadog"
  log_group_name  = aws_cloudwatch_log_group.auth_lambda.name
  destination_arn = local.datadog_forwarder_arn

  # Vazio: o log da Lambda ja e JSON estruturado na origem. Filtrar aqui
  # significaria decidir agora o que sera irrelevante no incidente de amanha.
  filter_pattern = ""
}
