# A camada efemera consome a persistente pelo mesmo contrato de SSM que os
# repositorios de aplicacao usam. Ler o state da outra camada tambem
# funcionaria, mas daria a este apply acesso a segredos que ele nao precisa ler.
data "aws_ssm_parameter" "api_gateway_id" {
  name = "${local.ssm_prefix}/api_gateway_id"
}

data "aws_ssm_parameter" "api_gateway_execution_arn" {
  name = "${local.ssm_prefix}/api_gateway_execution_arn"
}

data "aws_ssm_parameter" "jwt_secret_arn" {
  name = "${local.ssm_prefix}/jwt_secret_arn"
}

data "aws_ssm_parameter" "database_secret_arn" {
  name = "${local.ssm_prefix}/database_secret_arn"
}

data "aws_ssm_parameter" "public_base_url" {
  name = "${local.ssm_prefix}/public_base_url"
}

data "aws_ssm_parameter" "ses_configuration_set" {
  name = "${local.ssm_prefix}/ses_configuration_set"
}

data "aws_ssm_parameter" "ses_sender_email" {
  name = "${local.ssm_prefix}/ses_sender_email"
}

data "aws_secretsmanager_secret_version" "database" {
  secret_id = data.aws_ssm_parameter.database_secret_arn.value
}

data "aws_secretsmanager_secret_version" "jwt" {
  secret_id = data.aws_ssm_parameter.jwt_secret_arn.value
}

locals {
  database_credentials = jsondecode(data.aws_secretsmanager_secret_version.database.secret_string)
}
