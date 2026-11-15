data "aws_caller_identity" "current" {}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  arn_infix  = "${var.region}:${local.account_id}"

  services = {
    "os-service"        = { short = "os", database = true, dynamodb = false, subscribes = true, internal_token = true }
    "billing-service"   = { short = "billing", database = true, dynamodb = false, subscribes = false, internal_token = false }
    "execution-service" = { short = "execution", database = false, dynamodb = true, subscribes = false, internal_token = false }
  }

  repositories = merge(
    {
      infrastructure = "${var.project}-infrastructure"
      serverless     = "${var.project}-serverless"
      frontend       = "${var.project}-frontend"
    },
    { for repo in keys(local.services) : repo => "${var.project}-${repo}" },
  )

  deploy_roles = merge([
    for env, cfg in var.deploy_environments : {
      for repo, full_name in local.repositories : "${env}-${repo}" => {
        environment        = env
        repo               = repo
        full_name          = full_name
        branch             = cfg.branch
        github_environment = cfg.github_environment
        name               = "${var.project}-${env}-gha-${repo}"
      }
    }
  ]...)

  service_roles = {
    for key, role in local.deploy_roles : key => merge(role, local.services[role.repo])
    if contains(keys(local.services), role.repo)
  }
}

data "aws_iam_policy_document" "github_assume_role" {
  for_each = local.deploy_roles

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = concat(
        lookup(var.github_repository_ids, each.value.repo, null) == null ? [] : [
          "repo:${var.github_org}@${var.github_org_id}/${each.value.full_name}@${var.github_repository_ids[each.value.repo]}:ref:refs/heads/${each.value.branch}",
          "repo:${var.github_org}@${var.github_org_id}/${each.value.full_name}@${var.github_repository_ids[each.value.repo]}:environment:${each.value.github_environment}",
        ],
        [
          "repo:${var.github_org}/${each.value.full_name}:ref:refs/heads/${each.value.branch}",
          "repo:${var.github_org}/${each.value.full_name}:environment:${each.value.github_environment}",
        ],
      )
    }
  }
}

resource "aws_iam_role" "github" {
  for_each = local.deploy_roles

  name               = each.value.name
  description        = "Role assumida pelo CI de ${each.value.full_name} no ambiente ${each.value.environment}"
  assume_role_policy = data.aws_iam_policy_document.github_assume_role[each.key].json

  tags = { Environment = each.value.environment }
}

data "aws_iam_policy_document" "ssm_read" {
  for_each = var.deploy_environments

  statement {
    effect    = "Allow"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = ["arn:aws:ssm:${local.arn_infix}:parameter/${var.project}/${each.key}/*"]
  }
}

resource "aws_iam_policy" "ssm_read" {
  for_each = var.deploy_environments

  name   = "${var.project}-${each.key}-ssm-read"
  policy = data.aws_iam_policy_document.ssm_read[each.key].json

  tags = { Environment = each.key }
}

resource "aws_iam_role_policy_attachment" "ssm_read" {
  for_each = local.deploy_roles

  role       = aws_iam_role.github[each.key].name
  policy_arn = aws_iam_policy.ssm_read[each.value.environment].arn
}

data "aws_iam_policy_document" "serverless_deploy" {
  for_each = var.deploy_environments

  statement {
    effect = "Allow"
    actions = [
      "lambda:UpdateFunctionCode",
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:PublishVersion",
      "lambda:InvokeFunction",
    ]
    resources = ["arn:aws:lambda:${local.arn_infix}:function:${var.project}-${each.key}-auth"]
  }
}

resource "aws_iam_role_policy" "serverless_deploy" {
  for_each = var.deploy_environments

  name   = "deploy"
  role   = aws_iam_role.github["${each.key}-serverless"].id
  policy = data.aws_iam_policy_document.serverless_deploy[each.key].json
}

data "aws_iam_policy_document" "frontend_deploy" {
  for_each = var.deploy_environments

  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.project}-${each.key}-frontend"]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:DeleteObject", "s3:GetObject"]
    resources = ["arn:aws:s3:::${var.project}-${each.key}-frontend/*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]
    resources = ["arn:aws:cloudfront::${local.account_id}:distribution/*"]
  }
}

resource "aws_iam_role_policy" "frontend_deploy" {
  for_each = var.deploy_environments

  name   = "deploy"
  role   = aws_iam_role.github["${each.key}-frontend"].id
  policy = data.aws_iam_policy_document.frontend_deploy[each.key].json
}

resource "aws_iam_role_policy_attachment" "infrastructure_admin" {
  for_each = var.deploy_environments

  role       = aws_iam_role.github["${each.key}-infrastructure"].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
