locals {
  state_bucket_arn  = "arn:aws:s3:::${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
  state_lock_arn    = "arn:aws:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/${var.project}-tflock"
  service_arn_infix = "${var.region}:${data.aws_caller_identity.current.account_id}"
  internal_alb_name = substr("${local.name}-int", 0, 32)
}

data "aws_iam_policy_document" "service_deploy" {
  for_each = local.services

  statement {
    sid       = "StateList"
    actions   = ["s3:ListBucket"]
    resources = [local.state_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${var.environment}/${each.key}/*"]
    }
  }

  statement {
    sid       = "StateObject"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_bucket_arn}/${var.environment}/${each.key}/*"]
  }

  statement {
    sid       = "StateLock"
    actions   = ["dynamodb:DescribeTable", "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [local.state_lock_arn]
  }

  statement {
    sid       = "ReadOnly"
    actions   = ["ecr:GetAuthorizationToken", "eks:DescribeCluster", "eks:ListClusters", "ec2:Describe*", "elasticloadbalancing:Describe*", "ssm:DescribeParameters", "sts:GetCallerIdentity"]
    resources = ["*"]
  }

  statement {
    sid       = "Image"
    actions   = ["ecr:*"]
    resources = ["arn:aws:ecr:${local.service_arn_infix}:repository/${var.project}/${var.environment}/${each.key}"]
  }

  statement {
    sid       = "Contract"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:PutParameter", "ssm:DeleteParameter", "ssm:AddTagsToResource", "ssm:RemoveTagsFromResource", "ssm:ListTagsForResource"]
    resources = ["arn:aws:ssm:${local.service_arn_infix}:parameter${local.ssm_prefix}/${each.value.short}_*"]
  }

  statement {
    sid       = "Messaging"
    actions   = ["sqs:*", "sns:*"]
    resources = ["arn:aws:sqs:${local.service_arn_infix}:oficina-${var.environment}-${each.value.short}-*", "arn:aws:sns:${local.service_arn_infix}:oficina-${var.environment}-${each.value.short}-*"]
  }

  statement {
    sid       = "Secrets"
    actions   = ["secretsmanager:*"]
    resources = ["arn:aws:secretsmanager:${local.service_arn_infix}:secret:${var.project}/${var.environment}/${each.key}*"]
  }

  statement {
    sid       = "SharedSecrets"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = each.value.internal_token ? [aws_secretsmanager_secret.jwt.arn, aws_secretsmanager_secret.internal_service_token.arn] : [aws_secretsmanager_secret.jwt.arn]
  }

  statement {
    sid = "ServiceRole"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/oficina-${var.environment}-${each.value.short}*"]
  }

  statement {
    sid = "Network"
    actions = [
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:ModifySecurityGroupRules",
      "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
      "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["*"]
  }

  statement {
    sid = "Routing"
    actions = [
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:ModifyRule",
      "elasticloadbalancing:SetRulePriorities",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
    ]
    resources = [
      "arn:aws:elasticloadbalancing:${local.service_arn_infix}:targetgroup/oficina-${var.environment}-${each.value.short}*/*",
      "arn:aws:elasticloadbalancing:${local.service_arn_infix}:listener/app/${local.internal_alb_name}/*",
      "arn:aws:elasticloadbalancing:${local.service_arn_infix}:listener-rule/app/${local.internal_alb_name}/*",
    ]
  }

  dynamic "statement" {
    for_each = each.value.database ? [1] : []

    content {
      sid       = "Database"
      actions   = ["rds:*"]
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = each.value.dynamodb ? [1] : []

    content {
      sid       = "Table"
      actions   = ["dynamodb:*"]
      resources = ["arn:aws:dynamodb:${local.service_arn_infix}:table/oficina-${var.environment}-${each.value.short}*"]
    }
  }

  dynamic "statement" {
    for_each = each.value.subscribes ? [1] : []

    content {
      sid       = "Subscriptions"
      actions   = ["sns:Subscribe", "sns:Unsubscribe", "sns:GetTopicAttributes", "sns:GetSubscriptionAttributes", "sns:SetSubscriptionAttributes", "sns:ListSubscriptionsByTopic"]
      resources = ["arn:aws:sns:${local.service_arn_infix}:oficina-${var.environment}-*"]
    }
  }
}

resource "aws_iam_role_policy" "service_deploy" {
  for_each = local.services

  name   = "deploy"
  role   = aws_iam_role.github[each.key].id
  policy = data.aws_iam_policy_document.service_deploy[each.key].json
}
