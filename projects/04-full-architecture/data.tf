
# Read outputs from all three previous labs
data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "aws-arch-lab-tfstate"
    key    = "projects/01-vpc-foundation/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "data" {
  backend = "s3"
  config = {
    bucket = "aws-arch-lab-tfstate"
    key    = "projects/02-resilient-data/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "observability" {
  backend = "s3"
  config = {
    bucket = "aws-arch-lab-tfstate"
    key    = "projects/03-observability/terraform.tfstate"
    region = "us-east-1"
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  # Lab 1 outputs
  vpc_id             = data.terraform_remote_state.vpc.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.vpc.outputs.private_subnet_ids
  public_subnet_ids  = data.terraform_remote_state.vpc.outputs.public_subnet_ids
  alb_dns_name       = trimprefix(data.terraform_remote_state.vpc.outputs.alb_dns_name, "http://")

  # Computed values
  fqdn       = "${var.subdomain}.${var.domain_name}"
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
}
