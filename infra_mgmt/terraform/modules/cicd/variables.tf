variable "s3_git_bucket_name" {
  description = "Bucket name for S3 remote git repo."
  type        = string
}

variable "review_notification_emails" {
  description = "A list of email addresses to notify for git pushes to 'review/' branches."
  type        = list(string)
  default     = []
}

variable "codeartifact_domain_name" {
  description = "The name of the CodeArtifact domain."
  type        = string
}

variable "codeartifact_repository_name" {
  description = "The name of the CodeArtifact repository."
  type        = string
}

variable "codebuild_project_name" {
  description = "The name of the CodeBuild project."
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
