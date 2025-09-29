output "new_account_id" {
  description = "The 12-digit AWS account ID that was created."
  value       = aws_organizations_account.this.id
}

output "new_account_arn" {
  value       = aws_organizations_account.this.arn
  description = "ARN of the new AWS account."
}

output "assumable_role_arn" {
  description = "Role ARN to assume into the new account."
  value       = format("arn:aws:iam::%s:role/%s", aws_organizations_account.this.id, var.role_name)
}

output "landing_parent_id" {
  description = "The OU/ROOT where the account was placed."
  value       = aws_organizations_account.this.parent_id
}
