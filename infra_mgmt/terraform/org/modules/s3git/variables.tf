variable "s3_git_bucket_name" {
  description = "Bucket name for S3 remote git repo."
  type        = string
}

variable "review_notification_emails" {
  description = "A list of email addresses to notify for git pushes to 'review/' branches."
  type        = list(string)
  default     = []
}

