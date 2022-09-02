terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region                   = "us-east-2"
  profile                  = "default"
  shared_credentials_files = ["~/Terraform/Terraform/.aws/credentials"]
}

