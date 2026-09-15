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
  datadog_enabled = nonsensitive(data.aws_ssm_parameter.datadog_enabled.value) == "true"
  datadog_site    = nonsensitive(data.aws_ssm_parameter.datadog_site.value)

  datadog_secret_arn = nonsensitive(data.aws_ssm_parameter.datadog_secret_arn.value)

  datadog_forwarder_arn = nonsensitive(data.aws_ssm_parameter.datadog_forwarder_arn.value)

  datadog_secret_name = "datadog-api-key"

  dd_env     = var.environment
  dd_service = "monolith"

  dd_service_lambda = "auth-lambda"
}

locals {
  datadog_pod_labels = local.datadog_enabled ? {
    "tags.datadoghq.com/env"     = local.dd_env
    "tags.datadoghq.com/service" = local.dd_service
  } : {}

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

  values = [yamlencode({
    datadog = {
      site        = local.datadog_site
      clusterName = aws_eks_cluster.main.name

      apiKeyExistingSecret = local.datadog_secret_name

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

        containerCollectAll = true

        containerCollectUsingFiles = true
      }

      apm = {
        portEnabled   = true
        socketEnabled = true
      }

      processAgent = {
        enabled           = true
        processCollection = false
      }

      kubeStateMetricsCore = {
        enabled = true
      }

      kubeStateMetricsEnabled = false

      clusterChecks = {
        enabled = true
      }
    }

    clusterAgent = {
      enabled  = true
      replicas = 1

      metricsProvider = {
        enabled = false
      }
    }

    agents = {
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

  # O lb_controller entra aqui para serializar os dois charts. Sem isso o
  # Terraform sobe os dois em paralelo e os Services do Datadog batem no webhook
  # do controller antes dele ter endpoint (ver addons.tf).
  depends_on = [
    aws_eks_node_group.main,
    kubernetes_secret.datadog,
    helm_release.lb_controller,
  ]
}

resource "aws_cloudwatch_log_subscription_filter" "auth_lambda" {
  count = local.datadog_enabled && local.datadog_forwarder_arn != "unset" ? 1 : 0

  name            = "datadog"
  log_group_name  = aws_cloudwatch_log_group.auth_lambda.name
  destination_arn = local.datadog_forwarder_arn

  filter_pattern = ""
}
