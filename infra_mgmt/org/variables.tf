variable "existing_accounts" {
  type = map(object({
    account_id = string
    region     = string
  }))
  default = {
    org_management = { account_id = "000000000000", region = "us-west-2" }
  }
}

variable "account_email_domain" {
  type        = string
  description = "The email domain to use for new AWS accounts."
  default     = "example.com"
}
