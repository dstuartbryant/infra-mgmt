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

data "aws_caller_identity" "org_main" {
  provider = aws.org_main
}

data "aws_region" "org_main" {
  provider = aws.org_main
}

# 1. S3 Bucket for git-remote-s3
resource "aws_s3_bucket" "git_bucket" {
  provider = aws.org_main
  bucket   = var.s3_git_bucket_name
  tags = {
    IAMPolicy = "Developer"
  }
}

# 2. SNS Topic for Review Notifications
resource "aws_sns_topic" "git_review_pushes" {
  provider = aws.org_main
  name     = "git-review-pushes"
}

resource "aws_sns_topic_subscription" "email_subscriptions" {
  provider  = aws.org_main
  for_each  = toset(var.review_notification_emails)
  topic_arn = aws_sns_topic.git_review_pushes.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_sns_topic" "git_build_status" {
  provider = aws.org_main
  name     = "git-build-status"
}

resource "aws_sns_topic_subscription" "build_email_subscriptions" {
  provider  = aws.org_main
  for_each  = toset(var.build_notification_emails)
  topic_arn = aws_sns_topic.git_build_status.arn
  protocol  = "email"
  endpoint  = each.value
}

# 3. CodeArtifact for storing build packages
resource "aws_codeartifact_domain" "this" {
  provider = aws.org_main
  domain   = var.codeartifact_domain_name
}

resource "aws_codeartifact_repository" "this" {
  provider   = aws.org_main
  repository = var.codeartifact_repository_name
  domain     = aws_codeartifact_domain.this.domain
}

# 4. IAM Role and Policy for CodeBuild
resource "aws_iam_role" "codebuild_role" {
  provider = aws.org_main
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
  provider = aws.org_main
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
  provider   = aws.org_main
  role       = aws_iam_role.codebuild_role.name
  policy_arn = aws_iam_policy.codebuild_policy.arn
}

# 5. CodeBuild Project
resource "aws_codebuild_project" "this" {
  provider      = aws.org_main
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
  provider = aws.org_main
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
  provider = aws.org_main
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
        Action = "sns:Publish",
        Effect = "Allow",
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
  provider   = aws.org_main
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_lambda_function" "s3_git_handler" {
  provider         = aws.org_main
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "s3-git-cicd-handler"
  role             = aws_iam_role.lambda_role.arn
  handler          = "main.handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      SNS_TOPIC_ARN              = aws_sns_topic.git_review_pushes.arn
      SNS_BUILD_STATUS_TOPIC_ARN = aws_sns_topic.git_build_status.arn
      CODEBUILD_PROJECT_NAME     = aws_codebuild_project.this.name
    }
  }
}

resource "aws_lambda_permission" "s3_invoke_lambda" {
  provider      = aws.org_main
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_git_handler.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.git_bucket.arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  provider = aws.org_main
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
  provider = aws.org_main
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
  provider = aws.org_main
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
  provider   = aws.org_main
  role       = aws_iam_role.lambda_build_status_role.name
  policy_arn = aws_iam_policy.lambda_build_status_policy.arn
}

resource "aws_lambda_function" "build_status_handler" {
  provider         = aws.org_main
  filename         = data.archive_file.lambda_build_status_zip.output_path
  function_name    = "s3-git-build-status-handler"
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

# 7. EventBridge Rule to trigger Lambda on CodeBuild status change
resource "aws_cloudwatch_event_rule" "codebuild_status_change" {
  provider      = aws.org_main
  name          = "codebuild-status-change-rule"
  description   = "Trigger Lambda on CodeBuild build status change"
  event_pattern = jsonencode({
    "source" : ["aws.codebuild"],
    "detail-type" : ["CodeBuild Build State Change"],
    "detail" : {
      "project-name" : [var.codebuild_project_name],
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
  target_id = "s3-git-build-status-handler-target"
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



