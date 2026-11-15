# Copie para <ambiente>.tfvars e ajuste. Usado por platform/.
#
#   terraform -chdir=platform init -backend-config=homolog.s3.tfbackend
#   terraform -chdir=platform apply -var-file=../homolog.tfvars
#
# O backend E o var-file precisam apontar para o MESMO ambiente.

region      = "sa-east-1"
environment = "homolog"
project     = "oficina-mecanica"

ses_verified_emails = [
  # "fulano@example.com",
]

ses_sender_email = ""
