terraform {
  backend "s3" {
    bucket       = "aws-arch-lab-tfstate"
    key          = "projects/04-full-architecture/terraform.tfstate"
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

# CloudFront requires ACM certificates to be in us-east-1 regardless
# of where your other resources are — this is an AWS hard requirement
# We alias a second provider specifically for ACM certificate creation
provider "aws" {
  alias   = "us_east_1"
  region  = "us-east-1"
  profile = "aws-arch-lab-deployer"
}
