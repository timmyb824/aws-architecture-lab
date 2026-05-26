terraform {
  backend "s3" {
    bucket       = "aws-arch-lab-tfstate"
    key          = "projects/03-observability/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = "aws-arch-lab-deployer"
}
