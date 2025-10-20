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

output "codebuild_project_names" {
  description = "A map of repository names to CodeBuild project names."
  value       = { for repo, proj in aws_codebuild_project.this : repo => proj.name }
}

output "codepipeline_names" {
  description = "A map of repository names to CodePipeline names."
  value       = { for repo, pipe in aws_codepipeline.this : repo => pipe.name }
}

output "required_permission_set_statements" {
  description = "A list of IAM policy statements that should be applied to the developer permission set."
  value = [
    {
      Sid    = "CodeBuildReadOnlyAccess",
      Effect = "Allow",
      Action = [
        "codebuild:BatchGetBuilds",
        "codebuild:ListBuildsForProject",
        "codebuild:DescribeBuilds"
      ],
      Resource = "arn:aws:codebuild:${data.aws_region.org_main.name}:${data.aws_caller_identity.org_main.account_id}:project/${var.codebuild_project_prefix}-*"
    },
    {
      Sid    = "CodePipelineReadOnlyAccess",
      Effect = "Allow",
      Action = [
        "codepipeline:GetPipeline",
        "codepipeline:GetPipelineState",
        "codepipeline:ListActionExecutions"
      ],
      Resource = "arn:aws:codepipeline:${data.aws_region.org_main.name}:${data.aws_caller_identity.org_main.account_id}:${var.codebuild_project_prefix}-*"
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
      Resource = "arn:aws:logs:${data.aws_region.org_main.name}:${data.aws_caller_identity.org_main.account_id}:log-group:/aws/codebuild/${var.codebuild_project_prefix}-*:*"
    }
  ]
}