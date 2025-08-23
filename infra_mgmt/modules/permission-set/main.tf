variable "name" {}
variable "policy_arns" { type = list(string) }
variable "users" { type = list(any) }

data "aws_ssoadmin_instances" "main" {}

# Create the permission set
resource "aws_ssoadmin_permission_set" "this" {
  name         = var.name
  description  = "Permission set for ${var.name}"
  instance_arn = data.aws_ssoadmin_instances.main.arns[0]
}

# Attach each managed policy to the permission set
resource "aws_ssoadmin_managed_policy_attachment" "attachments" {
  for_each = toset(var.policy_arns)

  instance_arn       = data.aws_ssoadmin_instances.main.arns[0]
  permission_set_arn = aws_ssoadmin_permission_set.this.arn
  managed_policy_arn = each.value
}

# Assign the permission set to users
resource "aws_ssoadmin_account_assignment" "assignments" {
  for_each = { for u in var.users : u.email => u }
  instance_arn       = data.aws_ssoadmin_instances.main.arns[0]
  permission_set_arn = aws_ssoadmin_permission_set.this.arn
  principal_type     = "USER"
  principal_id       = each.value.id
  target_id          = each.value.account_id
  target_type        = "AWS_ACCOUNT"
}
