variable "account_id" {}
variable "alias" {}
variable "region" { default = "us-west-2" }

provider "aws" {
  alias  = var.alias
  region = var.region

  assume_role {
    role_arn = "arn:aws:iam::${var.account_id}:role/OrganizationAccountAccessRole"
  }
}
