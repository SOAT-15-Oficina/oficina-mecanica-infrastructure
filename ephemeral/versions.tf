terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  # Mesma razao de persistent/versions.tf: a key vem de -backend-config.
  #
  #   terraform -chdir=ephemeral init -backend-config=prod.s3.tfbackend
  #   terraform -chdir=ephemeral init -backend-config=homolog.s3.tfbackend
  backend "s3" {
    bucket         = "oficina-mecanica-tfstate-881757053222"
    region         = "sa-east-1"
    dynamodb_table = "oficina-mecanica-tflock"
    encrypt        = true
  }
}
