terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Mesmo bucket das outras stacks, key diferente. O bootstrap do bucket está
  # no README do `infra-k8s` (etapa T0) — ele é criado à mão, uma única vez.
  backend "s3" {
    bucket       = "tf-state-tech-challenge-fiap-679084116359"
    key          = "db/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      Stack     = "infra-db"
      ManagedBy = "terraform"
    }
  }
}

# Rede e cluster vêm do repositório `infra-k8s`.
#
# Esta é a dependência que define a ordem de deploy: sem o state do cluster
# publicado no S3, o `apply` daqui falha logo no plan. O erro típico é
# "Unable to find remote state" — significa que o pipeline do `infra-k8s`
# ainda não rodou, não que este repositório esteja quebrado.
data "terraform_remote_state" "k8s" {
  backend = "s3"

  config = {
    bucket = "tf-state-tech-challenge-fiap-679084116359"
    key    = "cluster/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  vpc_id             = data.terraform_remote_state.k8s.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.k8s.outputs.private_subnet_ids

  # No EKS Auto Mode as ENIs dos pods recebem o security group primário do
  # cluster. Se os pods deixarem de alcançar o banco, é o primeiro lugar para
  # olhar — a alternativa é o `node_security_group_id`, também exportado.
  eks_security_group_id = data.terraform_remote_state.k8s.outputs.cluster_primary_security_group_id
}
