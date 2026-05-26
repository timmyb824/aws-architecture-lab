# -----------------------------------------------------------------------------
# Read outputs from Lab 1's Terraform state
# This is how multi-layer architectures share values without hardcoding IDs
# -----------------------------------------------------------------------------
data "terraform_remote_state" "vpc" {
  backend = "s3"

  config = {
    bucket = "aws-arch-lab-tfstate"
    key    = "projects/01-vpc-foundation/terraform.tfstate"
    region = "us-east-1"
  }
}

# Convenience locals so we're not typing the full remote state path everywhere
locals {
  vpc_id             = data.terraform_remote_state.vpc.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.vpc.outputs.private_subnet_ids
  public_subnet_ids  = data.terraform_remote_state.vpc.outputs.public_subnet_ids
}
