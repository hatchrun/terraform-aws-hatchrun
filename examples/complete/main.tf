terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "hatchrun" {
  source = "../.."
}

output "role_arn" {
  value = module.hatchrun.role_arn
}

output "artifacts_bucket" {
  value = module.hatchrun.artifacts_bucket
}
