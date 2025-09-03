# ALL ACCOUNTS
terraform {
  required_version = ">= 1.13.0"
  backend "s3" {}
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_provider_region
  profile = var.aws_profile
}

module "account" {
  source = "./modules/account"
  providers = {
    aws = aws
  }
  for_each      = { for acc in var.accounts : acc.name => acc }
  account_name  = each.value.name
  account_email = each.value.email
}
