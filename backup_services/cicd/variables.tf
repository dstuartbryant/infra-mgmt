variable "project_name" {
  description = "The name of the project."
  type        = string
}

variable "env" {
  description = "The environment (e.g., 'dev', 'prod')."
  type        = string
}

variable "aws_region" {
  description = "The AWS region to deploy the resources to."
  type        = string
}

variable "tags" {
  description = "A map of tags to apply to the resources."
  type        = map(string)
  default     = {}
}

variable "repositories_config_path" {
  description = "The path to the YAML file containing the repository configurations."
  type        = string
}

variable "peer_review_email_list" {
  description = "A list of email addresses to notify for peer reviews."
  type        = list(string)
}
