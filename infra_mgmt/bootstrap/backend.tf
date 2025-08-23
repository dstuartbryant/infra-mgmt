variable "account_alias" {}
variable "region" { default = "us-west-2" }

provider "aws" {
  alias  = var.account_alias
  region = var.region

  assume_role {
    role_arn = "arn:aws:iam::${var.account_alias}:role/OrganizationAccountAccessRole"
  }
}

terraform {
  backend "s3" {
    bucket         = "tf-state-${var.account_alias}"
    key            = "terraform.tfstate"
    region         = var.region
    dynamodb_table = "tf-lock-${var.account_alias}"
    encrypt        = true
  }
}
