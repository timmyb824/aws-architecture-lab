# Read VPC details from Lab 1 state
data "terraform_remote_state" "vpc" {
  backend = "s3"

  config = {
    bucket = "aws-arch-lab-tfstate"
    key    = "projects/01-vpc-foundation/terraform.tfstate"
    region = "us-east-1"
  }
}

# Current AWS account ID and region — needed for IAM policies and ARN construction
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  vpc_id             = data.terraform_remote_state.vpc.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.vpc.outputs.private_subnet_ids
  account_id         = data.aws_caller_identity.current.account_id
  region             = data.aws_region.current.region
}
