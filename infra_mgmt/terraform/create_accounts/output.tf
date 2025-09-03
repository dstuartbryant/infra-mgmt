output "account_ids" {
  description = "Map of account name → new account ID"
  value       = { for name, acc in module.account : name => acc.new_account_id }
}

output "account_arns" {
  description = "Map of account name → new account ARN"
  value       = { for name, acc in module.account : name => acc.new_account_arn }
}

output "assumable_role_arns" {
  description = "Map of account name → assumable role ARN"
  value       = { for name, acc in module.account : name => acc.assumable_role_arn }
}

output "landing_parent_ids" {
  description = "Map of account name → landing parent ID"
  value       = { for name, acc in module.account : name => acc.landing_parent_id }
}
