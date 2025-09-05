terraform {
  required_version = ">= 1.13.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# 1. S3 Bucket for git-remote-s3
resource "aws_s3_bucket" "git_bucket" {
  bucket = var.s3_git_bucket_name
  tags = {
    IAMPolicy = "Developer"
  }
}

# 2. SNS Topic for Review Notifications
resource "aws_sns_topic" "git_review_pushes" {
  name = "git-review-pushes"
}

resource "aws_sns_topic_subscription" "email_subscriptions" {
  for_each  = toset(var.review_notification_emails)
  topic_arn = aws_sns_topic.git_review_pushes.arn
  protocol  = "email"
  endpoint  = each.value
}

# 3. CodeArtifact for storing build packages
resource "aws_codeartifact_domain" "this" {
  domain = var.codeartifact_domain_name
}

resource "aws_codeartifact_repository" "this" {
  repository = var.codeartifact_repository_name
  domain     = aws_codeartifact_domain.this.domain
}

# 4. IAM Role and Policy for CodeBuild
resource "aws_iam_role" "codebuild_role" {
  name = "${var.codebuild_project_name}-role"

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
  name = "${var.codebuild_project_name}-policy"

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
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Effect = "Allow",
        Resource = [
          aws_s3_bucket.git_bucket.arn,
          "${aws_s3_bucket.git_bucket.arn}/*"
        ]
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
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_policy_attachment" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = aws_iam_policy.codebuild_policy.arn
}

# 5. CodeBuild Project
resource "aws_codebuild_project" "this" {
  name          = var.codebuild_project_name
  service_role  = aws_iam_role.codebuild_role.arn
  build_timeout = "10" # in minutes

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  source {
    type      = "NO_SOURCE"
    buildspec = "buildspec.yaml"
  }
}

# 6. Lambda Function and related resources
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_iam_role" "lambda_role" {
  name = "s3-git-cicd-lambda-role"

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

resource "aws_iam_policy" "lambda_policy" {
  name = "s3-git-cicd-lambda-policy"

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
        Resource = aws_sns_topic.git_review_pushes.arn
      },
      {
        Action   = "codebuild:StartBuild",
        Effect   = "Allow",
        Resource = aws_codebuild_project.this.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_lambda_function" "s3_git_handler" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "s3-git-cicd-handler"
  role             = aws_iam_role.lambda_role.arn
  handler          = "main.handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      SNS_TOPIC_ARN          = aws_sns_topic.git_review_pushes.arn
      CODEBUILD_PROJECT_NAME = aws_codebuild_project.this.name
    }
  }
}

resource "aws_lambda_permission" "s3_invoke_lambda" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_git_handler.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.git_bucket.arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.git_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_git_handler.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.s3_invoke_lambda]
}

# 7. IAM Permissions for Developer Access to S3 Bucket
data "aws_ssoadmin_instances" "this" {}

data "aws_identitystore_group" "developer_groups" {
  for_each = toset([
    for group in local.groups_and_users.groups : group.display_name if strcontains(lower(group.display_name), "developer")
  ])
  identity_store_id = var.identitystore_id
  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = each.key
    }
  }
}

data "aws_identitystore_user" "developer_users" {
  for_each = local.group_memberships
  identity_store_id = var.identitystore_id
  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = each.value.user_name
    }
  }
}

data "aws_ssoadmin_permission_set" "developer_permission_sets" {
  for_each      = toset([for ps in data.aws_ssoadmin_permission_set.all : ps.name if strcontains(lower(ps.name), "developer")])
  instance_arn  = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  name          = each.key
}

resource "aws_iam_policy" "s3_developer_access" {
  name        = "s3-developer-access-for-${var.s3_git_bucket_name}"
  description = "Provides developer access to the S3 git bucket."

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
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
      }
    ]
  })
}

resource "aws_ssoadmin_managed_policy_attachment" "s3_developer_access" {
  for_each           = data.aws_ssoadmin_permission_set.developer_permission_sets
  instance_arn       = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  permission_set_arn = each.value.arn
  managed_policy_arn = aws_iam_policy.s3_developer_access.arn
}

locals {
  groups_and_users = jsondecode(data.http.iam_output.response_body)
  group_memberships = {
    for k, v in local.groups_and_users.group_memberships : k => {
      user_name  = split("-", k)[0]
      group_name = split("-", k)[1]
    }
  }
}

data "http" "iam_output" {
  url = "file://${path.module}/../../../.config/iam_output.json"
}

data "aws_ssoadmin_permission_set" "all" {
  for_each     = toset(keys(local.groups_and_users.permission_sets))
  instance_arn = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  name         = each.key
}
