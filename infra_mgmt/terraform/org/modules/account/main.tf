# ACCOUNT MODULE
terraform {
  required_version = ">= 1.13.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# -------------------------------------------------------------------
# Read existing Organization + ROOT so we can place the new account.
# (Avoids trying to "create" the org if it already exists.)
# -------------------------------------------------------------------
data "aws_organizations_organization" "org" {}

# Use either an explicit parent_id (OU or Root) or default to the first ROOT
locals {
  resolved_parent_id = coalesce(var.parent_id, try(data.aws_organizations_organization.org.roots[0].id, null))
}

# -------------------------------------------------------------------
# Create a new AWS account
# Notes:
# - email must be unique across ALL AWS accounts (never reused).
# - role_name will be created in the new account and trusted by the org
#   management account; you'll assume it to administer the new account.
# - close_on_deletion = true lets Terraform close the account on destroy
#   (irreversible after 90 days grace per AWS process).
# -------------------------------------------------------------------
resource "aws_organizations_account" "this" {
  name              = var.account_name
  email             = var.account_email
  role_name         = var.role_name
  close_on_deletion = var.close_on_deletion

  # If you want the new account to land in a specific OU, pass var.parent_id
  # with that OU's ID (e.g., "ou-xxxx-xxxxxxxx"). Otherwise it goes to ROOT.
  parent_id = local.resolved_parent_id

  tags = var.tags

  # Terraform will still create the role on new accounts, but for imported/existing 
  # accounts it won’t try to destroy/recreate. That's why this lifecycle block exists.
  lifecycle {
    ignore_changes = [
      role_name,
    ]
  }
}
