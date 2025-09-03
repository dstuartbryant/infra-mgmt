output "s3_git_bucket_name" {
  description = "Bucket name for S3 remote git repo."
  value       = var.s3_git_bucket_name
}

output "s3_git_bucket_arn" {
  description = "ARN for S3 git bucket"
  value       = aws_s3_bucket.pulse_private_git.arn
}
