# Copie para prod.tfvars e ajuste. Usado por persistent/.
#
#   terraform -chdir=persistent apply -var-file=../prod.tfvars

region      = "sa-east-1"
environment = "prod"
project     = "oficina-mecanica"
github_org  = "SOAT-15-Oficina"

# O SES esta em sandbox: SO entrega para os enderecos desta lista, com teto de
# 200 e-mails/24h. Cada um recebe um link de verificacao que alguem precisa
# clicar -- e um passo manual, uma vez por endereco.
ses_verified_emails = [
  # "fulano@example.com",
]

# Remetente dos e-mails de orcamento. Precisa estar na lista acima.
ses_sender_email = ""
