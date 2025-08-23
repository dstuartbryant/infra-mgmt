output "account_ids" {
  value = { for k, v in local.accounts : k => v.account_id }
}
