# Todos os objetos Kubernetes da aplicacao sao recursos Terraform deste
# repositorio -- inclusive Deployment, Service e HPA. Os repositorios de
# aplicacao nao guardam manifesto: eles buildam o artefato e trocam a imagem.

resource "kubernetes_namespace" "workshop" {
  metadata {
    name   = var.kube_namespace
    labels = { "app.kubernetes.io/name" = var.project }
  }
}

# --- Configuracao e segredos --------------------------------------------------

resource "kubernetes_config_map" "api" {
  metadata {
    name      = "api-config"
    namespace = kubernetes_namespace.workshop.metadata[0].name
  }

  data = {
    SERVER_ENVIRONMENT       = var.environment
    SERVER_PORT              = "8080"
    DATABASE_HOST            = aws_db_instance.main.address
    DATABASE_PORT            = tostring(aws_db_instance.main.port)
    DATABASE_NAME            = aws_db_instance.main.db_name
    DATABASE_MAX_CONNECTIONS = "5"

    # Base dos links de aprovacao enviados por e-mail ao cliente. E o dominio do
    # CloudFront + /api, porque esses links sao clicados fora do painel.
    APP_BASE_URL = "${data.aws_ssm_parameter.public_base_url.value}/api"

    EMAIL_PROVIDER     = "ses"
    AWS_DEFAULT_REGION = var.region
    SES_SENDER_EMAIL   = data.aws_ssm_parameter.ses_sender_email.value
    SES_REPLY_TO       = data.aws_ssm_parameter.ses_sender_email.value
    SES_CONFIG_SET     = data.aws_ssm_parameter.ses_configuration_set.value
  }
}

# O valor em claro passa pelo tfstate -- e por isso que o bucket de state tem
# versionamento, SSE e policy restrita (ver ../bootstrap).
resource "kubernetes_secret" "api" {
  metadata {
    name      = "api-secrets"
    namespace = kubernetes_namespace.workshop.metadata[0].name
  }

  data = {
    DATABASE_USER     = local.database_credentials.username
    DATABASE_PASSWORD = local.database_credentials.password

    # Mesmo valor que a Lambda usa para assinar. Um segredo, dois leitores.
    JWT_SECRET_KEY = data.aws_secretsmanager_secret_version.jwt.secret_string
  }

  type = "Opaque"
}

# --- IRSA: a API envia e-mail pelo SES sem credencial estatica ----------------

data "aws_iam_policy_document" "api_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.cluster.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.kube_namespace}:api"]
    }
  }
}

resource "aws_iam_role" "api" {
  name               = "${local.name}-api"
  assume_role_policy = data.aws_iam_policy_document.api_assume_role.json
}

data "aws_iam_policy_document" "api_ses" {
  statement {
    effect    = "Allow"
    actions   = ["ses:SendEmail", "ses:SendRawEmail"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "api_ses" {
  name   = "ses-send"
  role   = aws_iam_role.api.id
  policy = data.aws_iam_policy_document.api_ses.json
}

resource "kubernetes_service_account" "api" {
  metadata {
    name      = "api"
    namespace = kubernetes_namespace.workshop.metadata[0].name

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.api.arn
    }
  }
}

# --- Workload -----------------------------------------------------------------

resource "kubernetes_deployment" "api" {
  metadata {
    name      = local.api_deployment_name
    namespace = kubernetes_namespace.workshop.metadata[0].name
    labels    = local.app_labels
  }

  spec {
    replicas = var.api_replicas

    selector {
      match_labels = local.app_labels
    }

    template {
      metadata {
        labels = local.app_labels
      }

      spec {
        service_account_name = kubernetes_service_account.api.metadata[0].name

        container {
          name = "api"

          # Placeholder: sobe instantaneamente e nao serve nada. O primeiro
          # deploy do -monolith substitui a imagem via `kubectl set image`.
          image = local.placeholder_image

          port {
            name           = "http"
            container_port = 8080
          }

          env_from {
            config_map_ref { name = kubernetes_config_map.api.metadata[0].name }
          }

          env_from {
            secret_ref { name = kubernetes_secret.api.metadata[0].name }
          }

          resources {
            requests = { cpu = "100m", memory = "128Mi" }
            limits   = { cpu = "500m", memory = "256Mi" }
          }

          liveness_probe {
            http_get {
              path = "/ping"
              port = "http"
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/ready"
              port = "http"
            }
            initial_delay_seconds = 3
            period_seconds        = 5
            timeout_seconds       = 3
          }
        }
      }
    }
  }

  # A TAG DA IMAGEM E PROPRIEDADE DO PIPELINE DO -MONOLITH.
  #
  # O Terraform e dono da FORMA do Deployment (probes, recursos, envFrom,
  # ServiceAccount); a imagem e trocada por `kubectl set image` a cada release.
  # Sem este ignore_changes, o proximo apply desta camada reverteria a aplicacao
  # para o placeholder.
  #
  # replicas fica ignorado pelo mesmo motivo: quem manda nelas e o HPA.
  lifecycle {
    ignore_changes = [
      spec[0].template[0].spec[0].container[0].image,
      spec[0].replicas,
    ]
  }

  # Com a imagem placeholder nenhum pod fica Ready, e esperar pelo rollout
  # travaria o apply ate o timeout.
  wait_for_rollout = false
}

resource "kubernetes_service" "api" {
  metadata {
    name      = "api-service"
    namespace = kubernetes_namespace.workshop.metadata[0].name
    labels    = local.app_labels
  }

  spec {
    type     = "ClusterIP"
    selector = local.app_labels

    port {
      name        = "http"
      port        = 8080
      target_port = "http"
    }
  }
}

resource "kubernetes_horizontal_pod_autoscaler_v2" "api" {
  metadata {
    name      = "api-hpa"
    namespace = kubernetes_namespace.workshop.metadata[0].name
    labels    = local.app_labels
  }

  spec {
    min_replicas = 2
    max_replicas = 10

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.api.metadata[0].name
    }

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }

    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = 80
        }
      }
    }
  }

  depends_on = [helm_release.metrics_server]
}

# A ponte entre o ALB do Terraform e os pods: o AWS Load Balancer Controller
# reconcilia este CR mantendo o target group populado com os IPs dos pods do
# Service, sem criar balanceador nenhum.
# Aplicado por kubectl, e nao por um recurso de provider Kubernetes.
#
# Tanto `kubernetes_manifest` quanto `kubectl_manifest` precisam de conexao com
# o cluster em TEMPO DE PLANO -- o primeiro para validar o schema por dry-run,
# o segundo porque configura o provider de forma ansiosa. Aqui o cluster e o
# CRD TargetGroupBinding nascem neste mesmo apply, entao no plano nao ha
# endpoint algum: ambos falham. Nao e ordenacao, e fase; depends_on nao alcanca.
#
# Um local-exec nao configura conexao nenhuma no plano e roda depois que o
# cluster existe. O manifesto vai por variavel de ambiente para nao depender de
# indentacao de heredoc, e o kubeconfig e temporario para nao mexer no
# ~/.kube/config de quem aplica da propria maquina.
#
# Nao ha provisioner de destroy: o CR vive DENTRO do cluster e morre com ele. O
# passo "Detach target group binding first" do tear-down existe por outro
# motivo -- dar ao controller a chance de desregistrar os targets antes que o
# ALB seja removido.
resource "null_resource" "target_group_binding" {
  triggers = {
    manifest = local.target_group_binding_manifest
    cluster  = aws_eks_cluster.main.name
  }

  provisioner "local-exec" {
    environment = {
      MANIFEST = local.target_group_binding_manifest
      CLUSTER  = aws_eks_cluster.main.name
      REGION   = var.region
    }

    command = <<-EOT
      set -euo pipefail
      KUBECONFIG="$(mktemp)"
      export KUBECONFIG
      trap 'rm -f "$KUBECONFIG"' EXIT
      aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >/dev/null
      printf '%s' "$MANIFEST" | kubectl apply -f -
    EOT
  }

  depends_on = [helm_release.lb_controller, kubernetes_service.api]
}
