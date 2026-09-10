# Copie para <ambiente>.tfvars e ajuste. Usado por persistent/.
#
#   terraform -chdir=persistent init -backend-config=prod.s3.tfbackend
#   terraform -chdir=persistent apply -var-file=../prod.tfvars
#
# O backend E o var-file precisam apontar para o MESMO ambiente. Errar o par
# aplica a configuracao de um ambiente sobre o state do outro.
#
# No CI nada disto e usado: o workflow passa TF_VAR_environment e os valores de
# SES por variaveis de repositorio, porque *.tfvars e gitignored e nao existe no
# runner.

region      = "sa-east-1"
environment = "prod"
project     = "oficina-mecanica"
github_org  = "SOAT-15-Oficina"

# REMETENTES verificados no SES. A conta tem acesso de producao concedido, entao
# a entrega nao se limita a esta lista -- mas todo remetente precisa estar aqui.
# Cada endereco recebe um link de verificacao que alguem precisa clicar -- e um
# passo manual, uma vez por endereco.
ses_verified_emails = [
  # "fulano@example.com",
]

# Remetente dos e-mails de orcamento. Precisa estar na lista acima.
ses_sender_email = ""

# --- Para homologacao (homolog.tfvars) ---------------------------------------
#
# Mude apenas `environment`; o resto tem default derivado dele:
#
#   environment = "homolog"
#
#   deploy_branch         -> "hml"      (em prod: "main")
#   github_environment    -> "homolog"  (em prod: "production")
#   manage_ses_identities -> false      (em prod: true)
#
# `ses_verified_emails` e `ses_sender_email` continuam com os MESMOS valores de
# producao: a identidade e da conta, e homologacao envia por ela sem possui-la.
