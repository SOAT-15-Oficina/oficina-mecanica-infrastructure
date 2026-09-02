# Identidades SES verificadas.
#
# Vivem na camada PERSISTENTE por um motivo operacional concreto: destruir uma
# identidade a remove da conta, e recria-la exige que alguem clique num link
# enviado por e-mail. Num ambiente que sobe e desce a cada apresentacao, isso
# viraria um passo manual antes de toda demo.
#
# O SES esta em SANDBOX: entrega apenas para estes enderecos, com teto de 200
# e-mails/24h e 1/segundo. Endereco fora da lista recebe MessageRejected -- e o
# provider do monolito propaga esse erro em vez de engoli-lo.
# Identidade SES pertence a CONTA: so o ambiente dono as cria. Ver
# `manage_ses_identities` em variables.tf.
resource "aws_sesv2_email_identity" "verified" {
  for_each = local.manage_ses_identities ? toset(var.ses_verified_emails) : toset([])

  email_identity = each.value
}

# Agrupa as metricas de envio e da um gancho para event destinations depois.
resource "aws_sesv2_configuration_set" "main" {
  configuration_set_name = local.name

  delivery_options {
    tls_policy = "REQUIRE"
  }

  reputation_options {
    reputation_metrics_enabled = true
  }
}
