# IAM USERS AND GROUPS MODULE
# modules/iam_users_groups/main.tf

# modules/iam_sso/main.tf
terraform {
  required_version = ">= 1.13.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# -------------------------
# VARIABLES
# -------------------------

variable "groups" {
  description = "List of Identity Center groups to create"
  type        = list(string)
}

variable "group_accounts" {
  description = "Map of group name -> list of AWS account IDs the group should have access to"
  type        = map(list(string))
}


variable "users" {
  description = <<EOT
List of Identity Center users to create.
Each user object should contain:
- name   = Display name
- email  = Email address
- groups = list of groups to assign user to
EOT
  type = list(object({
    display_name = string
    user_name    = string
    name = object({
      given_name  = string
      family_name = string
    })
    email  = string
    groups = list(string)
  }))
}



variable "group_policy_arns" {
  description = "Optional map of group name -> list of policy ARNs for SSO Permission Sets"
  type        = map(list(string))
  default     = {}
}

# -------------------------
# DATA SOURCES
# -------------------------

data "aws_ssoadmin_instances" "main" {}

locals {
  instance_arn      = data.aws_ssoadmin_instances.main.arns[0]
  identity_store_id = data.aws_ssoadmin_instances.main.identity_store_ids[0]
}

# -------------------------
# IDENTITY CENTER GROUPS
# -------------------------

resource "aws_identitystore_group" "this" {
  for_each          = toset(var.groups)
  identity_store_id = local.identity_store_id
  display_name      = each.key
}

# -------------------------
# IDENTITY CENTER USERS
# -------------------------

resource "aws_identitystore_user" "this" {
  for_each          = { for u in var.users : u.user_name => u }
  identity_store_id = local.identity_store_id
  user_name         = each.value.user_name
  display_name      = each.value.display_name

  name {
    given_name  = each.value.name.given_name
    family_name = each.value.name.family_name
  }

  emails {
    value   = each.value.email
    primary = true
  }
}

# -------------------------
# GROUP MEMBERSHIPS
# -------------------------

resource "aws_identitystore_group_membership" "this" {
  for_each = merge([
    for u in var.users : {
      for g in u.groups : "${u.user_name}-${g}" => {
        user  = u.user_name
        group = g
      }
    }
  ]...)

  identity_store_id = local.identity_store_id
  group_id          = aws_identitystore_group.this[each.value.group].group_id
  member_id         = aws_identitystore_user.this[each.value.user].user_id
}

# -------------------------
# PERMISSION SETS
# -------------------------

resource "aws_ssoadmin_permission_set" "this" {
  for_each     = toset(var.groups)
  name         = each.key
  description  = "SSO permission set for ${each.key}"
  instance_arn = local.instance_arn
}

resource "aws_ssoadmin_managed_policy_attachment" "attachments" {
  for_each = merge([
    for group, arns in var.group_policy_arns : {
      for idx in range(length(arns)) : "${group}-${idx}" => {
        group = group
        arn   = arns[idx]
      }
    }
  ]...)

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.group].arn
  managed_policy_arn = each.value.arn
}

# -------------------------
# GROUP → ACCOUNT ASSIGNMENTS
# -------------------------

resource "aws_ssoadmin_account_assignment" "group_assignments" {
  for_each = merge([
    for group, accounts in var.group_accounts : {
      for account_id in accounts : "${group}-${account_id}" => {
        group   = group
        account = account_id
      }
    }
  ]...)

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.group].arn
  principal_type     = "GROUP"
  principal_id       = aws_identitystore_group.this[each.value.group].group_id
  target_type        = "AWS_ACCOUNT"
  target_id          = each.value.account
}
