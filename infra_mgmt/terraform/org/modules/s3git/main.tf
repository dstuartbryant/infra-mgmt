# S3 Git Bucket MODULE

terraform {
  required_version = ">= 1.13.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}


resource "aws_s3_bucket" "pulse_private_git" {
  bucket = var.s3_git_bucket_name

  tags = {
    IAMPolicy = "Developer"
  }
}

resource "aws_sns_topic" "git_review_pushes" {
  name = "git-review-pushes"
}

resource "aws_sns_topic_subscription" "email_subscriptions" {
  for_each  = toset(var.review_notification_emails)
  topic_arn = aws_sns_topic.git_review_pushes.arn
  protocol  = "email"
  endpoint  = each.value
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_iam_role" "lambda_role" {
  name = "git-review-push-lambda-role"

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
  name = "git-review-push-lambda-policy"

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
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_lambda_function" "git_push_notifier" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "git-review-push-notifier"
  role             = aws_iam_role.lambda_role.arn
  handler          = "main.handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.git_review_pushes.arn
    }
  }
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.pulse_private_git.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.git_push_notifier.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.s3_invoke_lambda]
}

resource "aws_lambda_permission" "s3_invoke_lambda" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.git_push_notifier.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.pulse_private_git.arn
}
