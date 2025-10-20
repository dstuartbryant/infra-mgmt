terraform {
  required_version = ">= 1.13.0"
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.0"
      configuration_aliases = [aws.org_main, aws.identity_center]
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.1"
    }
  }
}

locals {
  packages = keys(var.repositories)
}

data "aws_caller_identity" "org_main" {
  provider = aws.org_main
}

data "aws_region" "org_main" {
  provider = aws.org_main
}

# 1. SNS Topic for Build Status Notifications
resource "aws_sns_topic" "git_build_status" {
  provider = aws.org_main
  name     = "github-build-status"
}

resource "aws_sns_topic_subscription" "build_email_subscriptions" {
  provider  = aws.org_main
  for_each  = toset(var.build_notification_emails)
  topic_arn = aws_sns_topic.git_build_status.arn
  protocol  = "email"
  endpoint  = each.value
}

# 2. CodeArtifact for storing build packages
resource "aws_codeartifact_domain" "this" {
  provider = aws.org_main
  domain   = var.codeartifact_domain_name
}

resource "aws_codeartifact_repository" "this" {
  provider   = aws.org_main
  repository = var.codeartifact_repository_name
  domain     = aws_codeartifact_domain.this.domain
}

# 3. S3 Bucket for CodePipeline Artifacts
resource "aws_s3_bucket" "codepipeline_artifacts" {
  for_each = toset(local.packages)
  provider = aws.org_main
  bucket   = "${each.key}-pipeline-artifacts-${data.aws_caller_identity.org_main.account_id}"
}

# 4. IAM Roles and Policies
resource "aws_iam_role" "codebuild_role" {
  provider = aws.org_main
  name     = "${var.codebuild_project_prefix}-build-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "codebuild_policy" {
  provider = aws.org_main
  name     = "${var.codebuild_project_prefix}-build-policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "codeartifact:GetAuthorizationToken",
          "codeartifact:GetRepositoryEndpoint",
          "codeartifact:ReadFromRepository",
          "codeartifact:PublishPackageVersion"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Action   = "sts:GetServiceBearerToken",
        Effect   = "Allow",
        Resource = "*",
        Condition = {
          StringEquals = {
            "sts:AWSServiceName" = "codeartifact.amazonaws.com"
          }
        }
      },
      {
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketVersioning",
          "s3:PutObjectAcl",
          "s3:PutObject"
        ],
        Effect   = "Allow",
        Resource = [for b in aws_s3_bucket.codepipeline_artifacts : "${b.arn}/*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_policy_attachment" {
  provider   = aws.org_main
  role       = aws_iam_role.codebuild_role.name
  policy_arn = aws_iam_policy.codebuild_policy.arn
}

resource "aws_iam_role" "codepipeline_role" {
  provider = aws.org_main
  name     = "${var.codebuild_project_prefix}-pipeline-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "codepipeline.amazonaws.com" }
    }]
  })
}

resource "aws_iam_policy" "codepipeline_policy" {
  provider = aws.org_main
  name     = "${var.codebuild_project_prefix}-pipeline-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketVersioning",
          "s3:PutObjectAcl",
          "s3:PutObject"
        ],
        Effect   = "Allow",
        Resource = [for b in aws_s3_bucket.codepipeline_artifacts : "${b.arn}/*"]
      },
      {
        Action   = "codestar-connections:UseConnection",
        Effect   = "Allow",
        Resource = var.codestar_connection_arn
      },
      {
        Action   = "codebuild:BatchGetBuilds",
        Effect   = "Allow",
        Resource = [for p in aws_codebuild_project.this : p.arn]
      },
      {
        Action   = "codebuild:StartBuild",
        Effect   = "Allow",
        Resource = [for p in aws_codebuild_project.this : p.arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codepipeline_attachment" {
  provider   = aws.org_main
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = aws_iam_policy.codepipeline_policy.arn
}

# 5. CodeBuild Project
resource "aws_codebuild_project" "this" {
  for_each      = toset(local.packages)
  provider      = aws.org_main
  name          = "${var.codebuild_project_prefix}-${each.key}"
  service_role  = aws_iam_role.codebuild_role.arn
  build_timeout = "10" # in minutes

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-aarch64-standard:3.0"
    type                        = "ARM_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yaml"
  }
}

# 6. CodePipeline
resource "aws_codepipeline" "this" {
  for_each = toset(local.packages)
  provider = aws.org_main
  name     = "${var.codebuild_project_prefix}-${each.key}-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline_artifacts[each.key].bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output_${each.key}"]
      configuration = {
        ConnectionArn    = var.codestar_connection_arn
        FullRepositoryId = var.repositories[each.key]
        BranchName       = var.github_branch
      }
    }
  }

  stage {
    name = "Build"
    action {
      name            = "Build"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source_output_${each.key}"]
      configuration = {
        ProjectName = aws_codebuild_project.this[each.key].name
      }
    }
  }
}

# 7. Lambda Function for Build Status Notifications
data "archive_file" "lambda_build_status_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_build_status"
  output_path = "${path.module}/lambda_build_status.zip"
}

resource "aws_iam_role" "lambda_build_status_role" {
  provider = aws.org_main
  name     = "github-build-status-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_build_status_policy" {
  provider = aws.org_main
  name     = "github-build-status-lambda-policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action   = "sns:Publish",
        Effect   = "Allow",
        Resource = aws_sns_topic.git_build_status.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_build_status_policy_attachment" {
  provider   = aws.org_main
  role       = aws_iam_role.lambda_build_status_role.name
  policy_arn = aws_iam_policy.lambda_build_status_policy.arn
}

resource "aws_lambda_function" "build_status_handler" {
  provider         = aws.org_main
  filename         = data.archive_file.lambda_build_status_zip.output_path
  function_name    = "github-build-status-handler"
  role             = aws_iam_role.lambda_build_status_role.arn
  handler          = "main.handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.lambda_build_status_zip.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      SNS_BUILD_STATUS_TOPIC_ARN = aws_sns_topic.git_build_status.arn
    }
  }
}

# 8. EventBridge Rule to trigger Lambda on CodeBuild status change
resource "aws_cloudwatch_event_rule" "codebuild_status_change" {
  provider    = aws.org_main
  name        = "github-codebuild-status-change-rule"
  description = "Trigger Lambda on CodeBuild build status change"
  event_pattern = jsonencode({
    "source" : ["aws.codebuild"],
    "detail-type" : ["CodeBuild Build State Change"],
    "detail" : {
      "project-name" : [for repo in local.packages : "${var.codebuild_project_prefix}-${repo}"],
      "build-status" : [
        "SUCCEEDED",
        "FAILED",
        "STOPPED"
      ]
    }
  })
}

resource "aws_cloudwatch_event_target" "lambda_build_status" {
  provider  = aws.org_main
  rule      = aws_cloudwatch_event_rule.codebuild_status_change.name
  target_id = "github-build-status-handler-target"
  arn       = aws_lambda_function.build_status_handler.arn
}

resource "aws_lambda_permission" "allow_eventbridge_invoke_build_status" {
  provider      = aws.org_main
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.build_status_handler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.codebuild_status_change.arn
}
