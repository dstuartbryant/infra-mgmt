# CI/CD Terraform Module

This Terraform module provisions a CI/CD infrastructure on AWS.

## Features

- S3 bucket for use as a private Git remote.
- AWS CodeArtifact for storing package artifacts.
- AWS CodePipeline for CI/CD.
- Peer review notifications via email for branches starting with `review/`.
- Automated builds on pushes to the `main` branch.

## Usage

```hcl
module "cicd" {
  source = "./modules/services/cicd"

  project_name             = "my-project"
  env                      = "dev"
  aws_region               = "us-east-1"
  repositories_config_path = "configs/repositories.yaml"
  peer_review_email_list   = ["user1@example.com", "user2@example.com"]

  tags = {
    Terraform = "true"
  }
}
```

## Limitations

- **Git Repo Initialization:** This module does not handle the initialization of Git repositories in the S3 bucket. This needs to be done manually or by a separate process.
- **Lambda Function Code:** The Lambda function for sending peer review notifications is a placeholder. The actual code for the function needs to be written and packaged.
- **Buildspec:** The CodeBuild project does not have a `buildspec.yml` file defined. This file is needed to tell CodeBuild how to build and test the code.
- **Dynamic S3 Object Key:** The S3 object key in the CodePipeline source action is not fully dynamic yet. This will be addressed in a future update.
