# All groups with their IDs
output "groups" {
  description = "Map of Identity Center groups created (name => group_id)"
  value       = { for k, g in aws_identitystore_group.this : k => g.group_id }
}

# All users with their IDs and usernames
output "users" {
  description = "Map of Identity Center users created (user_name => user_id, display_name, email)"
  value = {
    for k, u in aws_identitystore_user.this : k => {
      user_id      = u.user_id
      user_name    = u.user_name
      display_name = u.display_name
      email        = u.emails[0].value
    }
  }
}

# Group memberships (user_name-group_name => membership_id)
output "group_memberships" {
  description = "Group memberships created (user_name-group => membership_id)"
  value       = { for k, m in aws_identitystore_group_membership.this : k => m.membership_id }
}

# Permission sets (group => permission_set_arn)
output "permission_sets" {
  description = "Permission sets created (group => permission_set_arn)"
  value       = { for k, p in aws_ssoadmin_permission_set.this : k => p.arn }
}

# Managed policy attachments (group-index => policy ARN attached)
output "policy_attachments" {
  description = "Managed policy attachments (group-index => policy ARN)"
  value       = { for k, a in aws_ssoadmin_managed_policy_attachment.attachments : k => a.managed_policy_arn }
}

# Account assignments (group-account => assignment ARN)
output "account_assignments" {
  description = "Account assignments (group-account => assignment ARN)"
  value       = { for k, a in aws_ssoadmin_account_assignment.group_assignments : k => a.id }
}
