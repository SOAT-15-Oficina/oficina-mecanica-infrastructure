data "aws_iam_policy_document" "service_deploy" {
  for_each = local.service_roles

  statement {
    sid       = "StateList"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${each.value.environment}/${each.value.repo}/*"]
    }
  }

  statement {
    sid       = "StateObject"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/${each.value.environment}/${each.value.repo}/*"]
  }

  statement {
    sid       = "StateLock"
    actions   = ["dynamodb:DescribeTable", "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [aws_dynamodb_table.state_lock.arn]
  }

  statement {
    sid       = "ReadOnly"
    actions   = ["ecr:GetAuthorizationToken", "eks:DescribeCluster", "eks:ListClusters", "ec2:Describe*", "elasticloadbalancing:Describe*", "ssm:DescribeParameters", "sts:GetCallerIdentity"]
    resources = ["*"]
  }

  statement {
    sid       = "Image"
    actions   = ["ecr:*"]
    resources = ["arn:aws:ecr:${local.arn_infix}:repository/${var.project}/${each.value.environment}/${each.value.repo}"]
  }

  statement {
    sid       = "Contract"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:PutParameter", "ssm:DeleteParameter", "ssm:AddTagsToResource", "ssm:RemoveTagsFromResource", "ssm:ListTagsForResource"]
    resources = ["arn:aws:ssm:${local.arn_infix}:parameter/${var.project}/${each.value.environment}/${each.value.short}_*"]
  }

  statement {
    sid       = "Messaging"
    actions   = ["sqs:*", "sns:*"]
    resources = ["arn:aws:sqs:${local.arn_infix}:oficina-${each.value.environment}-${each.value.short}-*", "arn:aws:sns:${local.arn_infix}:oficina-${each.value.environment}-${each.value.short}-*"]
  }

  statement {
    sid       = "Secrets"
    actions   = ["secretsmanager:*"]
    resources = ["arn:aws:secretsmanager:${local.arn_infix}:secret:${var.project}/${each.value.environment}/${each.value.repo}*"]
  }

  statement {
    sid     = "SharedSecrets"
    actions = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = concat(
      ["arn:aws:secretsmanager:${local.arn_infix}:secret:${var.project}-${each.value.environment}/jwt-secret-??????"],
      each.value.internal_token ? ["arn:aws:secretsmanager:${local.arn_infix}:secret:${var.project}/${each.value.environment}/internal-service-token-??????"] : [],
    )
  }

  statement {
    sid       = "BoundedServiceRole"
    actions   = ["iam:CreateRole", "iam:PutRolePolicy", "iam:PutRolePermissionsBoundary"]
    resources = ["arn:aws:iam::${local.account_id}:role/oficina-${each.value.environment}-${each.value.short}*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.service_boundary[each.value.environment].arn]
    }
  }

  statement {
    sid = "ServiceRole"
    actions = [
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = ["arn:aws:iam::${local.account_id}:role/oficina-${each.value.environment}-${each.value.short}*"]
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
      "arn:aws:elasticloadbalancing:${local.arn_infix}:targetgroup/oficina-${each.value.environment}-${each.value.short}*/*",
      "arn:aws:elasticloadbalancing:${local.arn_infix}:listener/app/${substr("${var.project}-${each.value.environment}-int", 0, 32)}/*",
      "arn:aws:elasticloadbalancing:${local.arn_infix}:listener-rule/app/${substr("${var.project}-${each.value.environment}-int", 0, 32)}/*",
    ]
  }

  dynamic "statement" {
    for_each = each.value.database ? [1] : []

    content {
      sid     = "Database"
      actions = ["rds:*"]
      resources = [
        "arn:aws:rds:${local.arn_infix}:db:oficina-${each.value.environment}-${each.value.short}",
        "arn:aws:rds:${local.arn_infix}:subgrp:oficina-${each.value.environment}-${each.value.short}",
        "arn:aws:rds:${local.arn_infix}:pg:default.*",
        "arn:aws:rds:${local.arn_infix}:og:default:*",
      ]
    }
  }

  dynamic "statement" {
    for_each = each.value.database ? [1] : []

    content {
      sid       = "DatabaseRead"
      actions   = ["rds:Describe*", "rds:ListTagsForResource"]
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = each.value.dynamodb ? [1] : []

    content {
      sid       = "Table"
      actions   = ["dynamodb:*"]
      resources = ["arn:aws:dynamodb:${local.arn_infix}:table/oficina-${each.value.environment}-${each.value.short}*"]
    }
  }

  dynamic "statement" {
    for_each = each.value.subscribes ? [1] : []

    content {
      sid       = "Subscriptions"
      actions   = ["sns:Subscribe", "sns:Unsubscribe", "sns:GetTopicAttributes", "sns:GetSubscriptionAttributes", "sns:SetSubscriptionAttributes", "sns:ListSubscriptionsByTopic"]
      resources = ["arn:aws:sns:${local.arn_infix}:oficina-${each.value.environment}-*"]
    }
  }
}

resource "aws_iam_role_policy" "service_deploy" {
  for_each = local.service_roles

  name   = "deploy"
  role   = aws_iam_role.github[each.key].id
  policy = data.aws_iam_policy_document.service_deploy[each.key].json
}
