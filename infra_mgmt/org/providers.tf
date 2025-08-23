module "aws_providers" {
  source     = "../modules/aws_provider"
  for_each   = local.accounts
  account_id = each.value.account_id
  alias      = each.key
  region     = each.value.region
}
