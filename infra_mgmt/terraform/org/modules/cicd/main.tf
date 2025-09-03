# CICD MODULE
terraform {
  required_version = ">= 1.13.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

module "s3git" {
  source             = "../s3git"
  s3_git_bucket_name = var.s3_git_bucket_name

}
