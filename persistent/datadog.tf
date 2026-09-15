locals {
  datadog_enabled = var.datadog_enabled

  dd_env = var.environment

  dd_services = {
    api    = "monolith"
    lambda = "auth-lambda"
  }

  datadog_notification_targets = length(var.datadog_notification_targets) > 0 ? var.datadog_notification_targets : (
    var.ses_sender_email != "" ? ["@${var.ses_sender_email}"] : []
  )

  dd_notify = join(" ", local.datadog_notification_targets)

  dd_tags = [
    "env:${local.dd_env}",
    "project:${var.project}",
    "managed_by:terraform",
  ]

  manage_datadog_aws_integration = local.datadog_enabled && (
    var.manage_datadog_aws_integration == null ? local.is_production : var.manage_datadog_aws_integration
  )

  manage_datadog_logs_metrics = local.datadog_enabled && (
    var.manage_datadog_logs_metrics == null ? local.is_production : var.manage_datadog_logs_metrics
  )

  datadog_aws_principal = "464622532012"

  datadog_integration_role_name = "${local.name}-datadog-integration"
  datadog_forwarder_name        = "${local.name}-datadog-forwarder"
}

resource "aws_secretsmanager_secret" "datadog" {
  count = local.datadog_enabled ? 1 : 0

  name                    = "${local.name}/datadog-api-key"
  description             = "Chave de API do Datadog, lida pelo agente no cluster e pelo Forwarder"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "datadog" {
  count = local.datadog_enabled ? 1 : 0

  secret_id = aws_secretsmanager_secret.datadog[0].id

  secret_string = var.datadog_api_key

  lifecycle {
    precondition {
      condition     = var.datadog_api_key != ""
      error_message = "datadog_enabled = true exige TF_VAR_datadog_api_key. Para subir sem Datadog, passe TF_VAR_datadog_enabled=false."
    }
  }
}

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
      lambdas = var.datadog_forward_cloudwatch_logs ? [
        aws_cloudformation_stack.datadog_forwarder[0].outputs["DatadogForwarderArn"]
      ] : []

      sources = []
    }
  }

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

resource "aws_cloudformation_stack" "datadog_forwarder" {
  count = local.datadog_enabled && var.datadog_forward_cloudwatch_logs ? 1 : 0

  name = local.datadog_forwarder_name

  capabilities = ["CAPABILITY_IAM", "CAPABILITY_NAMED_IAM", "CAPABILITY_AUTO_EXPAND"]

  template_url = var.datadog_forwarder_template_url

  parameters = {
    DdApiKeySecretArn = aws_secretsmanager_secret.datadog[0].arn
    DdSite            = var.datadog_site
    FunctionName      = local.datadog_forwarder_name

    DdTags = join(",", [
      "env:${local.dd_env}",
      "project:${var.project}",
      "managed_by:terraform",
    ])

    RedactEmail = "true"
    RedactIp    = "true"
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_log_subscription_filter" "api_access" {
  count = local.datadog_enabled && var.datadog_forward_cloudwatch_logs ? 1 : 0

  name            = "datadog"
  log_group_name  = aws_cloudwatch_log_group.api_access.name
  destination_arn = aws_cloudformation_stack.datadog_forwarder[0].outputs["DatadogForwarderArn"]

  filter_pattern = ""
}

locals {
  datadog_forwarder_arn = local.datadog_enabled && var.datadog_forward_cloudwatch_logs ? (
    aws_cloudformation_stack.datadog_forwarder[0].outputs["DatadogForwarderArn"]
  ) : "unset"

  datadog_parameters = {
    datadog_enabled       = local.datadog_enabled ? "true" : "false"
    datadog_site          = var.datadog_site
    datadog_secret_arn    = local.datadog_enabled ? aws_secretsmanager_secret.datadog[0].arn : "unset"
    datadog_forwarder_arn = local.datadog_forwarder_arn

    # O teste sintetico mudou para a camada efemera (ephemeral/datadog_synthetics.tf)
    # e precisa dos mesmos destinatarios de alerta. Contrato por SSM, como o resto
    # (ADR-0007). Vazio e valor valido: o monitor sobe sem @destinatario.
    datadog_notify = local.dd_notify != "" ? local.dd_notify : "unset"
  }
}

resource "aws_ssm_parameter" "datadog" {
  for_each = local.datadog_parameters

  name  = "${local.ssm_prefix}/${each.key}"
  type  = "String"
  value = each.value
}
