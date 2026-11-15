locals {
  datadog_secret_name = "datadog-api-key"
}

resource "kubernetes_secret" "datadog" {
  count = local.datadog_enabled ? 1 : 0

  metadata {
    name      = local.datadog_secret_name
    namespace = "kube-system"
  }

  data = {
    "api-key" = var.datadog_api_key
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
      site        = var.datadog_site
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

  depends_on = [
    aws_eks_node_group.main,
    kubernetes_secret.datadog,
    helm_release.lb_controller,
  ]
}

resource "aws_cloudwatch_log_subscription_filter" "auth_lambda" {
  count = local.datadog_enabled && var.datadog_forward_cloudwatch_logs ? 1 : 0

  name            = "datadog"
  log_group_name  = aws_cloudwatch_log_group.auth_lambda.name
  destination_arn = aws_cloudformation_stack.datadog_forwarder[0].outputs["DatadogForwarderArn"]

  filter_pattern = ""
}
