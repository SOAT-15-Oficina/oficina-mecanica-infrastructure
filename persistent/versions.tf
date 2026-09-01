terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Bucket e tabela criados por ../bootstrap.
  #
  # A `key` fica FORA do bloco de proposito: cada ambiente tem o proprio state,
  # e qual deles usar e escolhido no init.
  #
  #   terraform -chdir=persistent init -backend-config=prod.s3.tfbackend
  #   terraform -chdir=persistent init -backend-config=homolog.s3.tfbackend
  #
  # Sem -backend-config o init PERGUNTA a key; com -input=false (como no CI) ele
  # falha. Os dois comportamentos sao melhores que herdar um state por engano.
  backend "s3" {
    bucket         = "oficina-mecanica-tfstate-881757053222"
    region         = "sa-east-1"
    dynamodb_table = "oficina-mecanica-tflock"
    encrypt        = true
  }
}
