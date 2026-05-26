# Run with: AWS_PROFILE=arch-lab

terraform {
  backend "s3" {
    bucket       = "aws-arch-lab-tfstate"
    key          = "projects/02-resilient-data/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = "aws-arch-lab-deployer"
}


