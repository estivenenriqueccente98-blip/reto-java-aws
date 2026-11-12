terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Terraform init completara bucket, region y key desde GitHub Actions.
  # S3 locking nativo, sin necesidad de DynamoDB.
  backend "s3" {
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "reto-java-aws"
      ManagedBy = "terraform"
      Purpose   = "technical-challenge"
    }
  }
}
