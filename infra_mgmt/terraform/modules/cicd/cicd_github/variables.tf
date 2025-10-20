variable "repositories" {
  description = "A map of package names to their full GitHub repository identifiers (e.g., 'owner/repo')."
  type        = map(string)
}

variable "github_branch" {
  description = "The branch to monitor in each repository."
  type        = string
  default     = "main"
}

variable "codestar_connection_arn" {
  description = "The ARN of the AWS CodeStar Connections connection to GitHub."
  type        = string
}

variable "review_notification_emails" {
  description = "A list of email addresses to notify for git pushes to 'review/' branches."
  type        = list(string)
  default     = ["stuart+unclassDev1@spacewego.com"]
}

variable "build_notification_emails" {
  description = "A list of email addresses to notify for CodeBuild status changes."
  type        = list(string)
  default     = ["stuart+unclassDev1@spacewego.com"]
}

variable "codeartifact_domain_name" {
  description = "The name of the CodeArtifact domain."
  type        = string
}

variable "codeartifact_repository_name" {
  description = "The name of the CodeArtifact repository."
  type        = string
}

variable "codebuild_project_prefix" {
  description = "The prefix for the CodeBuild project names."
  type        = string
}

variable "identitystore_id" {
  description = "The ID of the IAM Identity Center store."
  type        = string
}

variable "iam_output_json_path" {
  description = "The path to the iam_output.json file."
  type        = string
}