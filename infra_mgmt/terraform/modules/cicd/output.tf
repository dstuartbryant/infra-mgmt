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

output "codeartifact_region" {
  description = "The AWS region the CodeArtifact repository is in."
  value       = data.aws_region.org_main
}

output "codebuild_project_name" {
  description = "The name of the CodeBuild project."
  value       = aws_codebuild_project.this.name
}

output "required_permission_set_statements" {
  description = "A list of IAM policy statements that should be applied to the developer permission set."
  value = [
    {
      Sid    = "ListBucketsInConsole",
      Effect = "Allow",
      Action = [
        "s3:ListAllMyBuckets"
      ],
      Resource = "*"
    },
    {
      Sid    = "GitS3ObjectAccess",
      Effect = "Allow",
      Action = [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject"
      ],
      Resource = "${aws_s3_bucket.git_bucket.arn}/*"
    },
    {
      Sid    = "GitS3ListAccess",
      Effect = "Allow",
      Action = [
        "s3:ListBucket"
      ],
      Resource = [
        aws_s3_bucket.git_bucket.arn
      ]
    },
    {
      Sid    = "CodeBuildReadOnlyAccess",
      Effect = "Allow",
      Action = [
        "codebuild:BatchGetBuilds",
        "codebuild:ListBuildsForProject",
        "codebuild:DescribeBuilds"
      ],
      Resource = aws_codebuild_project.this.arn
    },
    {
      Sid    = "CloudWatchLogsListAccess",
      Effect = "Allow",
      Action = [
        "logs:DescribeLogGroups"
      ],
      Resource = "*"
    },
    {
      Sid    = "CloudWatchLogsReadOnlyAccess",
      Effect = "Allow",
      Action = [
        "logs:GetLogEvents",
        "logs:DescribeLogStreams"
      ],
      Resource = "arn:aws:logs:${data.aws_region.org_main.name}:${data.aws_caller_identity.org_main.account_id}:log-group:/aws/codebuild/${var.codebuild_project_name}:*"
    }
  ]
}
