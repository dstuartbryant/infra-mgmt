terraform {
  backend "s3" {
    bucket         = "terraform-state-pulse"
    key            = "org/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
    profile        = "pulse-infra-admin"
  }
}
