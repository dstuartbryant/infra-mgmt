variable "project" {}
variable "classification" {}
variable "access" {}
variable "services" {
  type    = list(any)
  default = []
}
variable "provider_alias" {}

# Deploy permission sets
module "permission_sets" {
  source = "../permission-set"
  for_each = var.access.roles
  name        = each.key
  policy_arns = each.value.policy_arns
  users       = [
    for u in var.access.users : u
    if contains(u.projects, var.project)
  ]
  providers   = { aws = aws }
}

# Deploy services
module "services" {
  for_each = { for s in var.services : s.name => s }
  source   = "../services/${each.key}"
  config   = each.value
  providers = { aws = aws }
}
