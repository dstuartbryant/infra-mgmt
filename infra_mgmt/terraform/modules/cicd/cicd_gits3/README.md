# Terraform Module: CICD

This module provisions a comprehensive, event-driven CI/CD pipeline within an AWS account. The pipeline is designed to work with `git-remote-s3`, using an S3 bucket as the central Git repository.

## Architecture Overview

The workflow is entirely serverless and orchestrated through S3 events and Lambda functions:

1.  **Git Push**: A developer pushes a commit to the S3 bucket using `git-remote-s3`.
2.  **S3 Event**: The `s3:ObjectCreated:*` event triggers the primary Lambda function (`s3-git-cicd-handler`).
3.  **Lambda Orchestration**: The Lambda function inspects the object key to determine the repository and branch name.
    - If the push is to a `review/*` branch, it sends a notification to an SNS topic.
    - If the push is to the `main` branch, it triggers a new build in the AWS CodeBuild project.
4.  **CodeBuild Execution**: The CodeBuild project clones the repository from S3 and executes the `buildspec.yaml` found in the repository's root. It is configured to use AWS CodeArtifact for package management.
5.  **Build Status Notifications**: An EventBridge rule monitors the CodeBuild project for state changes (Succeeded, Failed, Stopped). On a state change, it triggers a second Lambda function (`s3-git-build-status-handler`) which sends a detailed notification to another SNS topic.

## Resources Created

-   **S3 Bucket**: Serves as the remote Git repository.
-   **SNS Topics**: Two topics for notifications: one for pushes to review branches and one for build status updates.
-   **CodeArtifact Domain & Repository**: For storing and managing build artifacts and packages.
-   **CodeBuild Project**: A generic build environment that can execute any `buildspec.yaml`.
-   **Lambda Functions**:
    -   `s3-git-cicd-handler`: The main orchestrator triggered by S3 events.
    -   `s3-git-build-status-handler`: Sends notifications based on build status.
-   **IAM Roles & Policies**: Necessary permissions for CodeBuild and Lambda to access other AWS services.
-   **EventBridge Rule**: To capture CodeBuild state changes.
-   **SSO Permission Set Inline Policy**: Grants developers the necessary permissions to use the S3 bucket, view build logs, and interact with the pipeline.

## Input Variables

| Name                         | Description                                                                 | Type           | Default | Required |
| ---------------------------- | --------------------------------------------------------------------------- | -------------- | ------- | :------: |
| `s3_git_bucket_name`         | The name for the S3 bucket that will serve as the Git remote.               | `string`       | n/a     |   yes    |
| `review_notification_emails` | A list of email addresses to notify for pushes to `review/*` branches.      | `list(string)` | `[]`    |    no    |
| `build_notification_emails`  | A list of email addresses to notify for CodeBuild status changes.           | `list(string)` | `[]`    |    no    |
| `codeartifact_domain_name`   | The name of the CodeArtifact domain.                                        | `string`       | n/a     |   yes    |
| `codeartifact_repository_name` | The name of the CodeArtifact repository.                                    | `string`       | n/a     |   yes    |
| `codebuild_project_name`     | The name of the CodeBuild project.                                          | `string`       | n/a     |   yes    |
| `identitystore_id`           | The ID of the IAM Identity Center store, used for permission lookups.       | `string`       | n/a     |   yes    |
| `iam_output_json_path`       | The relative path to the `iam_output.json` file from the `iam-apply` step. | `string`       | n/a     |   yes    |

## Outputs

| Name                         | Description                                  |
| ---------------------------- | -------------------------------------------- |
| `s3_git_bucket_name`         | The name of the created S3 bucket.           |
| `s3_git_bucket_arn`          | The ARN of the created S3 bucket.            |
| `codeartifact_domain_name`   | The name of the created CodeArtifact domain. |
| `codeartifact_repository_name` | The name of the created CodeArtifact repository. |
| `codebuild_project_name`     | The name of the created CodeBuild project.   |
