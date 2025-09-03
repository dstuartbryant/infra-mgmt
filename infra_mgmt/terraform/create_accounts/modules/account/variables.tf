variable "management_region" {
  description = "Region for the management account provider (any commercial region)."
  type        = string
  default     = "us-east-1"
}

variable "account_name" {
  description = "Friendly name for the new AWS account."
  type        = string
}

variable "account_email" {
  description = "Unique email address for the new AWS account (must not be used by any other AWS account)."
  type        = string
}

variable "role_name" {
  description = "IAM role to create in the new account and trust from the management account."
  type        = string
  default     = "OrganizationAccountAccessRole"
}

variable "close_on_deletion" {
  description = <<EOT
Whether to close the AWS account when the Terraform resource is destroyed.
If true, Terraform will initiate account closure (irreversible after ~90 days).
If false, the account will remain even if the resource is destroyed.
EOT
  type        = bool
  default     = true
}


variable "parent_id" {
  description = "Optional OU or ROOT ID where the account should be created (e.g., ou-xxxx-xxxxxxxx or r-xxxx). Leave null to use the default ROOT."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to the new account resource in Organizations."
  type        = map(string)
  default     = {}
}
