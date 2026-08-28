# Autenticacao dos pipelines por OIDC. Nenhum dos quatro repositorios guarda
# access key: cada um assume a propria role, restrita ao que aquele pipeline
# precisa fazer.

data "aws_caller_identity" "current" {}

# O provider OIDC do GitHub e um recurso *singleton por conta*: a AWS so aceita
# um por URL. Esta conta ja tinha o dele desde 2025-05-14, criado por outro
# projeto -- a role `GithubActions` (que confia em `repo:emershoww/*`) depende
# dele.
#
# Por isso ele e lido, nao criado. Se esta stack o possuisse, um
# `terraform destroy` aqui derrubaria o CI/CD do outro projeto junto, e um
# `apply` sobrescreveria a thumbprint list dele.
#
# Se um dia esta stack rodar numa conta limpa, crie-o uma vez a mao:
#   aws iam create-open-id-connect-provider \
#     --url https://token.actions.githubusercontent.com \
#     --client-id-list sts.amazonaws.com
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# Confia apenas em workflows da branch main do repositorio correspondente --
# nao em qualquer ref, e nem em PR de fork.
data "aws_iam_policy_document" "github_assume_role" {
  for_each = local.repositories

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
      values = [
        "repo:${var.github_org}/${each.value}:ref:refs/heads/main",
        "repo:${var.github_org}/${each.value}:environment:production",
      ]
    }
  }
}

resource "aws_iam_role" "github" {
  for_each = local.repositories

  name               = "${local.name}-gha-${each.key}"
  description        = "Role assumida pelo CI de ${each.value}"
  assume_role_policy = data.aws_iam_policy_document.github_assume_role[each.key].json
}

# Todos os pipelines leem o contrato de recursos no SSM.
data "aws_iam_policy_document" "ssm_read" {
  statement {
    effect    = "Allow"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = ["arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_prefix}/*"]
  }
}

resource "aws_iam_policy" "ssm_read" {
  name   = "${local.name}-ssm-read"
  policy = data.aws_iam_policy_document.ssm_read.json
}

resource "aws_iam_role_policy_attachment" "ssm_read" {
  for_each = local.repositories

  role       = aws_iam_role.github[each.key].name
  policy_arn = aws_iam_policy.ssm_read.arn
}

# --- monolith: publica imagem no ECR e faz rollout no EKS -------------------

data "aws_iam_policy_document" "monolith_deploy" {
  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [aws_ecr_repository.api.arn]
  }

  # O acesso ao cluster em si e concedido por EKS access entry na camada
  # efemera; aqui basta poder descrever o cluster para montar o kubeconfig.
  statement {
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "monolith_deploy" {
  name   = "deploy"
  role   = aws_iam_role.github["monolith"].id
  policy = data.aws_iam_policy_document.monolith_deploy.json
}

# --- serverless: so troca o codigo da funcao --------------------------------

data "aws_iam_policy_document" "serverless_deploy" {
  statement {
    effect = "Allow"
    actions = [
      "lambda:UpdateFunctionCode",
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:PublishVersion",
      "lambda:InvokeFunction",
    ]
    resources = ["arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:${local.name}-auth"]
  }
}

resource "aws_iam_role_policy" "serverless_deploy" {
  name   = "deploy"
  role   = aws_iam_role.github["serverless"].id
  policy = data.aws_iam_policy_document.serverless_deploy.json
}

# --- frontend: escreve no bucket e invalida o CloudFront --------------------

data "aws_iam_policy_document" "frontend_deploy" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.frontend.arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:DeleteObject", "s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]
    resources = [aws_cloudfront_distribution.site.arn]
  }
}

resource "aws_iam_role_policy" "frontend_deploy" {
  name   = "deploy"
  role   = aws_iam_role.github["frontend"].id
  policy = data.aws_iam_policy_document.frontend_deploy.json
}

# --- infrastructure: aplica o Terraform --------------------------------------
#
# Amplo por natureza: e o repositorio que cria tudo. O freio nao e IAM, e o
# required reviewer do GitHub Environment "production" antes do apply.
resource "aws_iam_role_policy_attachment" "infrastructure_admin" {
  role       = aws_iam_role.github["infrastructure"].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
