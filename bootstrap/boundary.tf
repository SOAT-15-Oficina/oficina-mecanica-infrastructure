data "aws_iam_policy_document" "service_boundary" {
  for_each = var.deploy_environments

  statement {
    sid       = "Queues"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:ChangeMessageVisibility", "sqs:GetQueueAttributes", "sqs:GetQueueUrl", "sqs:SendMessage"]
    resources = ["arn:aws:sqs:${local.arn_infix}:oficina-${each.key}-*"]
  }

  statement {
    sid       = "Topics"
    actions   = ["sns:Publish"]
    resources = ["arn:aws:sns:${local.arn_infix}:oficina-${each.key}-*"]
  }

  statement {
    sid = "Tables"
    actions = [
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:ConditionCheckItem",
    ]
    resources = ["arn:aws:dynamodb:${local.arn_infix}:table/oficina-${each.key}-*"]
  }

  statement {
    sid       = "Email"
    actions   = ["ses:SendEmail", "ses:SendRawEmail"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "service_boundary" {
  for_each = var.deploy_environments

  name        = "${var.project}-${each.key}-service-boundary"
  description = "Teto de permissoes das roles IRSA criadas pelo infra/ de cada servico em ${each.key}"
  policy      = data.aws_iam_policy_document.service_boundary[each.key].json
}
