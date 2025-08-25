variable "config" {
  type = object({
    repo_name = string
    domain    = string
    role_arn  = string
  })
}

# CodeArtifact repository
resource "aws_codeartifact_repository" "repo" {
  domain = var.config.domain
  repository = var.config.repo_name
}

# S3 bucket for pipeline artifacts
resource "aws_s3_bucket" "artifact_bucket" {
  bucket = "${var.config.repo_name}-artifacts"
}

# Enable versioning
resource "aws_s3_bucket_versioning" "artifact_bucket_versioning" {
  bucket = aws_s3_bucket.artifact_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "artifact_bucket_sse" {
  bucket = aws_s3_bucket.artifact_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}



# IAM Role assumed by CodePipeline
resource "aws_iam_role" "pipeline_role" {
  name = "${var.config.repo_name}-pipeline-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "codepipeline.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# CodePipeline
resource "aws_codepipeline" "pipeline" {
  name     = "${var.config.repo_name}-pipeline"
  role_arn = aws_iam_role.pipeline_role.arn
  artifact_store {
    type = "S3"
    location = aws_s3_bucket.artifact_bucket.bucket
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        RepositoryName = var.config.repo_name
        BranchName     = "main"
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
        ProjectName = "${var.config.repo_name}-build"
      }
    }
  }
}
