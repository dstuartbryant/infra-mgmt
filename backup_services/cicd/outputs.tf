output "s3_bucket_name" {
  description = "The name of the S3 bucket used for the Git remote."
  value       = aws_s3_bucket.git_remote.bucket
}

output "codeartifact_domain_name" {
  description = "The name of the CodeArtifact domain."
  value       = aws_codeartifact_domain.main.domain
}

output "codeartifact_repository_name" {
  description = "The name of the CodeArtifact repository."
  value       = aws_codeartifact_repository.main.repository
}

output "codepipeline_name" {
  description = "The name of the CodePipeline."
  value       = aws_codepipeline.main.name
}
