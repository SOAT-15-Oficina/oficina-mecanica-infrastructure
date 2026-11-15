data "aws_sesv2_email_identity" "verified" {
  for_each = toset(var.ses_verified_emails)

  email_identity = each.value

  lifecycle {
    postcondition {
      condition     = self.verified_for_sending_status
      error_message = "A identidade SES ${each.value} existe mas nao esta verificada: clique no link de verificacao enviado ao endereco antes do bring-up."
    }
  }
}

resource "aws_sesv2_configuration_set" "main" {
  configuration_set_name = local.name

  delivery_options {
    tls_policy = "REQUIRE"
  }

  reputation_options {
    reputation_metrics_enabled = true
  }
}
