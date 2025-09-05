output "s3_git_bucket_name" {
  description = "Bucket name for S3 remote git repo."
  value       = aws_s3_bucket.git_bucket.id
}

output "s3_git_bucket_arn" {
  description = "ARN for S3 git bucket"
  value       = aws_s3_bucket.git_bucket.arn
}

output "codeartifact_domain_name" {
  description = "The name of the CodeArtifact domain."
  value       = aws_codeartifact_domain.this.domain
}

output "codeartifact_repository_name" {
  description = "The name of the CodeArtifact repository."
  value       = aws_codeartifact_repository.this.repository
}

output "codebuild_project_name" {
  description = "The name of the CodeBuild project."
  value       = aws_codebuild_project.this.name
}
