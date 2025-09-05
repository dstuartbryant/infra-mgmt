terraform {
  required_version = ">= 1.13.0"
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.0"
      configuration_aliases = [aws.org_west, aws.identity_center]
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.1"
    }
  }
}

data "aws_caller_identity" "org_west" {
  provider = aws.org_west
}

data "aws_region" "org_west" {
  provider = aws.org_west
}

# 1. S3 Bucket for git-remote-s3
resource "aws_s3_bucket" "git_bucket" {
  provider = aws.org_west
  bucket   = var.s3_git_bucket_name
  tags = {
    IAMPolicy = "Developer"
  }
}

# 2. SNS Topic for Review Notifications
resource "aws_sns_topic" "git_review_pushes" {
  provider = aws.org_west
  name     = "git-review-pushes"
}

resource "aws_sns_topic_subscription" "email_subscriptions" {
  provider  = aws.org_west
  for_each  = toset(var.review_notification_emails)
  topic_arn = aws_sns_topic.git_review_pushes.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_sns_topic" "git_build_status" {
  provider = aws.org_west
  name     = "git-build-status"
}

resource "aws_sns_topic_subscription" "build_email_subscriptions" {
  provider  = aws.org_west
  for_each  = toset(var.build_notification_emails)
  topic_arn = aws_sns_topic.git_build_status.arn
  protocol  = "email"
  endpoint  = each.value
}

# 3. CodeArtifact for storing build packages
resource "aws_codeartifact_domain" "this" {
  provider = aws.org_west
  domain   = var.codeartifact_domain_name
}

resource "aws_codeartifact_repository" "this" {
  provider   = aws.org_west
  repository = var.codeartifact_repository_name
  domain     = aws_codeartifact_domain.this.domain
}

# 4. IAM Role and Policy for CodeBuild
resource "aws_iam_role" "codebuild_role" {
  provider = aws.org_west
  name     = "${var.codebuild_project_name}-role"

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
  provider = aws.org_west
  name     = "${var.codebuild_project_name}-policy"

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
  provider   = aws.org_west
  role       = aws_iam_role.codebuild_role.name
  policy_arn = aws_iam_policy.codebuild_policy.arn
}

# 5. CodeBuild Project
resource "aws_codebuild_project" "this" {
  provider      = aws.org_west
  name          = var.codebuild_project_name
  service_role  = aws_iam_role.codebuild_role.arn
  build_timeout = "10" # in minutes

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  source {
    type      = "NO_SOURCE"
    buildspec = <<-EOT
      version: 0.2
      phases:
        install:
          runtime-versions:
            python: 3.12
          commands:
            - pip install git-remote-s3 pyyaml
        build:
          commands:
            - echo "Cloning repository $${REPO_NAME} from S3 bucket $${S3_BUCKET_NAME}"
            - git clone "s3://$${S3_BUCKET_NAME}/$${REPO_NAME}" repo
            - cd repo
            - |
              cat > run_buildspec.py <<'EOF'
              import yaml
              import subprocess
              import sys
              import os

              def run_commands(commands):
                  for command in commands:
                      print(f"Executing: {command}", flush=True)
                      proc = subprocess.run(command, shell=True, check=False, text=True, capture_output=True)
                      print(proc.stdout)
                      print(proc.stderr, file=sys.stderr)
                      if proc.returncode != 0:
                          print(f"Command failed with exit code {proc.returncode}", file=sys.stderr)
                          sys.exit(proc.returncode)

              buildspec_path = 'buildspec.yaml'
              if not os.path.exists(buildspec_path):
                  print(f"No {buildspec_path} found. Nothing to do.")
                  sys.exit(0)

              with open(buildspec_path, 'r') as f:
                  buildspec = yaml.safe_load(f)

              phases = ['install', 'pre_build', 'build', 'post_build']
              for phase_name in phases:
                  if phase_name in buildspec.get('phases', {}):
                      print(f"--- Running phase: {phase_name} ---", flush=True)
                      phase_config = buildspec['phases'][phase_name]
                      
                      if 'runtime-versions' in phase_config:
                          print(f"Runtime versions specified: {phase_config['runtime-versions']}")

                      if 'commands' in phase_config:
                          run_commands(phase_config['commands'])
              EOF
            - python run_buildspec.py
    EOT
  }
}

# 6. Lambda Function and related resources
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_iam_role" "lambda_role" {
  provider = aws.org_west
  name     = "s3-git-cicd-lambda-role"

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
  provider = aws.org_west
  name     = "s3-git-cicd-lambda-policy"

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
        Resource = [
          aws_sns_topic.git_review_pushes.arn,
          aws_sns_topic.git_build_status.arn
        ]
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
  provider   = aws.org_west
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_lambda_function" "s3_git_handler" {
  provider         = aws.org_west
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
      SNS_BUILD_STATUS_TOPIC_ARN = aws_sns_topic.git_build_status.arn
      CODEBUILD_PROJECT_NAME = aws_codebuild_project.this.name
    }
  }
}

resource "aws_lambda_permission" "s3_invoke_lambda" {
  provider      = aws.org_west
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_git_handler.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.git_bucket.arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  provider = aws.org_west
  bucket   = aws_s3_bucket.git_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_git_handler.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.s3_invoke_lambda]
}

# 6a. Lambda Function for Build Status Notifications
data "archive_file" "lambda_build_status_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_build_status"
  output_path = "${path.module}/lambda_build_status.zip"
}

resource "aws_iam_role" "lambda_build_status_role" {
  provider = aws.org_west
  name     = "s3-git-build-status-lambda-role"

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
  provider = aws.org_west
  name     = "s3-git-build-status-lambda-policy"

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
  provider   = aws.org_west
  role       = aws_iam_role.lambda_build_status_role.name
  policy_arn = aws_iam_policy.lambda_build_status_policy.arn
}

resource "aws_lambda_function" "build_status_handler" {
  provider         = aws.org_west
  filename         = data.archive_file.lambda_build_status_zip.output_path
  function_name    = "s3-git-build-status-handler"
  role             = aws_iam_role.lambda_build_status_role.arn
  handler          = "main.handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.lambda_build_status_zip.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      SNS_BUILD_STATUS_TOPIC_ARN = aws_sns_topic.git_build_status.arn
    }
  }
}

# 7. IAM Permissions for Developer Access to S3 Bucket
data "aws_ssoadmin_instances" "this" {
  provider = aws.identity_center
}

data "aws_identitystore_group" "developer_groups" {
  provider = aws.identity_center
  for_each = toset([
    for group_name in keys(local.groups_and_users.iam_groups.value) : group_name if strcontains(lower(group_name), "developer")
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
  provider          = aws.identity_center
  for_each          = local.parsed_group_memberships
  identity_store_id = var.identitystore_id
  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = each.value.user_name
    }
  }
}

data "aws_ssoadmin_permission_set" "developer_permission_sets" {
  provider     = aws.identity_center
  for_each     = toset([for ps in data.aws_ssoadmin_permission_set.all : ps.name if strcontains(lower(ps.name), "developer")])
  instance_arn = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  name         = each.key
}

# 8. EventBridge Rule for CodeBuild Status
resource "aws_cloudwatch_event_rule" "codebuild_state_change" {
  provider    = aws.org_west
  name        = "codebuild-state-change"
  description = "Capture CodeBuild state changes"

  event_pattern = jsonencode({
    source      = ["aws.codebuild"],
    "detail-type" = ["CodeBuild Build State Change"],
    detail      = {
      "project-name" = [var.codebuild_project_name],
      "build-status" = ["SUCCEEDED", "FAILED", "STOPPED"]
    }
  })
}

resource "aws_cloudwatch_event_target" "lambda" {
  provider = aws.org_west
  rule     = aws_cloudwatch_event_rule.codebuild_state_change.name
  arn      = aws_lambda_function.build_status_handler.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_lambda" {
  provider      = aws.org_west
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.build_status_handler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.codebuild_state_change.arn
}

resource "aws_ssoadmin_permission_set_inline_policy" "cicd_developer_access" {
  provider           = aws.identity_center
  for_each           = data.aws_ssoadmin_permission_set.developer_permission_sets
  instance_arn       = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  permission_set_arn = each.value.arn

  inline_policy = jsonencode({
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
        Resource = "arn:aws:logs:${data.aws_region.org_west.name}:${data.aws_caller_identity.org_west.account_id}:log-group:/aws/codebuild/${var.codebuild_project_name}:*"
      }
    ]
  })
}

locals {
  groups_and_users = jsondecode(data.local_file.iam_output.content)
  parsed_group_memberships = {
    for k, v in local.groups_and_users.iam_group_memberships.value : k => {
      user_name  = split("-", k)[0]
      group_name = split("-", k)[1]
    }
  }
}

data "local_file" "iam_output" {
  filename = var.iam_output_json_path
}

data "aws_ssoadmin_permission_set" "all" {
  provider     = aws.identity_center
  for_each     = toset(keys(local.groups_and_users.iam_permission_sets.value))
  instance_arn = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  name         = each.key
}