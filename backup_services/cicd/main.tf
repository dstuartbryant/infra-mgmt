locals {
  repositories = yamldecode(file(var.repositories_config_path))
}

resource "aws_s3_bucket" "git_remote" {
  bucket = "${var.project_name}-${var.env}-git-remote"

  tags = var.tags
}

resource "aws_codeartifact_domain" "main" {
  domain = "${var.project_name}-${var.env}"
  tags   = var.tags
}

resource "aws_codeartifact_repository" "main" {
  repository = "${var.project_name}-${var.env}"
  domain     = aws_codeartifact_domain.main.domain
  tags       = var.tags
}

resource "aws_iam_role" "codepipeline_role" {
  name = "${var.project_name}-${var.env}-codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_policy" "codepipeline_policy" {
  name = "${var.project_name}-${var.env}-codepipeline-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketVersioning",
          "s3:PutObject"
        ]
        Effect   = "Allow"
        Resource = [
          aws_s3_bucket.git_remote.arn,
          "${aws_s3_bucket.git_remote.arn}/*"
        ]
      },
      {
        Action = [
          "codebuild:StartBuild",
          "codebuild:StopBuild",
          "codebuild:BatchGetBuilds",
          "codebuild:RetryBuild"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codepipeline_attachment" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = aws_iam_policy.codepipeline_policy.arn
}

resource "aws_iam_role" "codebuild_role" {
  name = "${var.project_name}-${var.env}-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_policy" "codebuild_policy" {
  name = "${var.project_name}-${var.env}-codebuild-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "codeartifact:GetAuthorizationToken",
          "codeartifact:GetRepositoryEndpoint",
          "codeartifact:ReadFromRepository"
        ]
        Effect   = "Allow"
        Resource = [
          aws_codeartifact_domain.main.arn,
          aws_codeartifact_repository.main.arn
        ]
      },
      {
        Action = [
          "sts:GetServiceBearerToken"
        ]
        Effect = "Allow"
        Resource = "*"
        Condition = {
          StringEquals = {
            "sts:services" = "codeartifact.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_attachment" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = aws_iam_policy.codebuild_policy.arn
}

resource "aws_codebuild_project" "main" {
  for_each = local.repositories

  name          = "${var.project_name}-${var.env}-${each.key}-build"
  service_role  = aws_iam_role.codebuild_role.arn
  build_timeout = "5"
  source_version = "main"

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
    type     = "S3"
    location = "${aws_s3_bucket.git_remote.id}/${each.key}"
  }

  tags = var.tags
}

resource "aws_codepipeline" "main" {
  for_each = local.repositories

  name     = "${var.project_name}-${var.env}-${each.key}-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.git_remote.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "S3"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        S3Bucket    = aws_s3_bucket.git_remote.bucket
        S3ObjectKey = "${each.key}/refs/heads/main"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]

      configuration = {
        ProjectName = aws_codebuild_project.main[each.key].name
      }
    }
  }
}

resource "aws_sns_topic" "peer_review_notifications" {
  name = "${var.project_name}-${var.env}-peer-review-notifications"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "peer_review_email" {
  for_each = toset(var.peer_review_email_list)

  topic_arn = aws_sns_topic.peer_review_notifications.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_iam_role" "eventbridge_lambda_role" {
  name = "${var.project_name}-${var.env}-eventbridge-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_lambda_function" "peer_review_notifier" {
  filename      = "notify_peer_review.zip" # Placeholder
  function_name = "${var.project_name}-${var.env}-peer-review-notifier"
  role          = aws_iam_role.eventbridge_lambda_role.arn
  handler       = "index.handler"
  runtime       = "python3.8"

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.peer_review_notifications.arn
    }
  }

  tags = var.tags
}

resource "aws_cloudwatch_event_rule" "main_branch_push" {
  for_each = local.repositories

  name        = "${var.project_name}-${var.env}-${each.key}-main-branch-push"
  description = "Trigger CodePipeline on main branch push for ${each.key}"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["s3.amazonaws.com"]
      eventName   = ["PutObject"]
      requestParameters = {
        bucketName = [aws_s3_bucket.git_remote.bucket]
        key        = ["${each.key}/refs/heads/main"]
      }
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "codepipeline_target" {
  for_each = local.repositories

  rule     = aws_cloudwatch_event_rule.main_branch_push[each.key].name
  target_id = "CodePipeline"
  arn      = aws_codepipeline.main[each.key].arn
  role_arn = aws_iam_role.codepipeline_role.arn
}

resource "aws_cloudwatch_event_rule" "review_branch_push" {
  name        = "${var.project_name}-${var.env}-review-branch-push"
  description = "Trigger notification on review branch push"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["s3.amazonaws.com"]
      eventName   = ["PutObject"]
      requestParameters = {
        bucketName = [aws_s3_bucket.git_remote.bucket]
        key        = [{ "prefix" : "refs/heads/review/" }]
      }
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule     = aws_cloudwatch_event_rule.review_branch_push.name
  target_id = "Lambda"
  arn      = aws_lambda_function.peer_review_notifier.arn
}


