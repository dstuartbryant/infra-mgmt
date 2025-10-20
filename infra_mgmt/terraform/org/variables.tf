variable "aws_provider_region" {
  description = "The AWS region that changes will be made in for your AWS account."
  type        = string
}

variable "aws_profile" {
  description = "Local .aws/config profile to use."
  type        = string
}

variable "accounts" {
  description = "List of accounts with name, email, and optional parent_id"
  type = list(object({
    name      = string
    email     = string
    parent_id = optional(string)
  }))
}