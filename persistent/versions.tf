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
  backend "s3" {
    bucket         = "oficina-mecanica-tfstate-881757053222"
    key            = "persistent/terraform.tfstate"
    region         = "sa-east-1"
    dynamodb_table = "oficina-mecanica-tflock"
    encrypt        = true
  }
}
