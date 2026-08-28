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
    # `kubernetes_manifest` exige acesso a API do cluster em TEMPO DE PLANO --
    # ele valida o schema por dry-run server-side. Como o cluster e o CRD
    # TargetGroupBinding nascem neste mesmo apply, isso e impossivel: o plano
    # falha com "cannot create REST client: no client config".
    #
    # `kubectl_manifest` aplica so em tempo de apply e nao precisa do CRD
    # registrado no plano, que e exatamente o caso aqui.
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
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
  }

  backend "s3" {
    bucket         = "oficina-mecanica-tfstate-881757053222"
    key            = "ephemeral/terraform.tfstate"
    region         = "sa-east-1"
    dynamodb_table = "oficina-mecanica-tflock"
    encrypt        = true
  }
}
