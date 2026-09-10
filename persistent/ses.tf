# Identidades SES verificadas.
#
# Vivem na camada PERSISTENTE por um motivo operacional concreto: destruir uma
# identidade a remove da conta, e recria-la exige que alguem clique num link
# enviado por e-mail. Num ambiente que sobe e desce sob demanda, isso viraria um
# passo manual antes de todo bring-up.
#
# A conta tem ACESSO DE PRODUCAO concedido no SES (sa-east-1): 50.000 e-mails/24h
# a 14/segundo, e entrega para qualquer destinatario. Esta lista sao os
# REMETENTES -- e o remetente continua precisando de verificacao. MessageRejected
# ainda acontece (remetente nao verificado, destinatario suprimido, conta
# pausada), e o provider do monolito propaga esse erro em vez de engoli-lo.
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
