# Terraform Module: CICD for GitHub using AWS CodePipeline

This module provisions a comprehensive, event-driven CI/CD pipeline within an AWS account, triggered by commits to a GitHub repository. It uses AWS CodePipeline to automate the build and deployment process.

## Architecture Overview

The workflow is orchestrated using native AWS services, primarily AWS CodePipeline:

1.  **Git Push**: A developer pushes a commit to a connected GitHub repository's specified branch (e.g., `main`).
2.  **CodeStar Connection**: A pre-configured AWS CodeStar Connection securely links AWS to the GitHub repository.
3.  **CodePipeline Trigger**: AWS CodePipeline automatically detects the new commit through the CodeStar Connection and triggers a new pipeline execution.
4.  **Source Stage**: The pipeline's first stage downloads the source code from the specific commit and stores it as an artifact in an S3 bucket.
5.  **Build Stage**: The pipeline's second stage triggers an AWS CodeBuild project.
6.  **CodeBuild Execution**: The CodeBuild project retrieves the source artifact from S3 and executes the `buildspec.yaml` found in the repository's root. It is also configured to use AWS CodeArtifact for package management.
7.  **Build Status Notifications**: An Amazon EventBridge rule monitors the CodeBuild project for state changes (Succeeded, Failed, Stopped). On a state change, it triggers a Lambda function (`github-build-status-handler`) which sends a detailed notification to an SNS topic.

## Resources Created

-   **AWS CodePipeline**: One pipeline per repository to orchestrate the source and build stages.
-   **S3 Bucket**: An artifact store for each CodePipeline.
-   **SNS Topic**: A topic for build status update notifications.
-   **CodeArtifact Domain & Repository**: For storing and managing build artifacts and packages.
-   **CodeBuild Project**: A build environment for each repository, configured to be triggered by CodePipeline.
-   **Lambda Function**:
    -   `github-build-status-handler`: Sends notifications based on build status.
-   **IAM Roles & Policies**: Necessary permissions for CodePipeline, CodeBuild, and Lambda to interact with other AWS services.
-   **EventBridge Rule**: To capture CodeBuild state changes.

## Prerequisites

Before using this module, you need to manually create an AWS CodeStar Connection to GitHub.

**Steps to create the connection:**

1.  **Navigate to Developer Tools:** In the AWS Management Console, search for **Developer Tools**.
2.  **Find Connections:** On the Developer Tools page, find and click on **Connections** in the left-hand sidebar under "Tools".
3.  **Create Connection:**
    *   Click the **Create connection** button.
    *   Select **GitHub** as the provider.
    *   Enter a **Connection name** (e.g., `my-github-connection`).
    *   Click **Connect to GitHub**. A new window will open, prompting you to install the "AWS Connector for GitHub" app on your GitHub account or organization. Authorize it for the repositories you intend to use.
4.  **Get the ARN:** Once the connection is successfully created and in the **Available** state, click on its name. The **ARN** will be displayed in the summary section.

Copy this full ARN and use it as the value for the `codestar_connection_arn` variable.

## Input Variables

| Name                         | Description                                                                 | Type           | Default | Required |
| ---------------------------- | --------------------------------------------------------------------------- | -------------- | ------- | :------: |
| `repositories`               | A map of package names to their full GitHub repository identifiers (e.g., 'owner/repo'). | `map(string)`  | n/a     |   yes    |
| `github_branch`              | The branch to monitor in each repository.                                   | `string`       | `main`  |    no    |
| `codestar_connection_arn`    | The ARN of the AWS CodeStar Connections connection to GitHub.               | `string`       | n/a     |   yes    |
| `review_notification_emails` | A list of email addresses to notify for pushes to `review/*` branches.      | `list(string)` | `[]`    |    no    |
| `build_notification_emails`  | A list of email addresses to notify for CodeBuild status changes.           | `list(string)` | `[]`    |    no    |
| `codeartifact_domain_name`   | The name of the CodeArtifact domain.                                        | `string`       | n/a     |   yes    |
| `codeartifact_repository_name` | The name of the CodeArtifact repository.                                    | `string`       | n/a     |   yes    |
| `codebuild_project_prefix`   | The prefix for the CodeBuild project names.                                 | `string`       | n/a     |   yes    |
| `identitystore_id`           | The ID of the IAM Identity Center store, used for permission lookups.       | `string`       | n/a     |   yes    |
| `iam_output_json_path`       | The relative path to the `iam_output.json` file from the `iam-apply` step. | `string`       | n/a     |   yes    |

## Outputs

| Name                         | Description                                  |
| ---------------------------- | -------------------------------------------- |
| `codeartifact_domain_name`   | The name of the created CodeArtifact domain. |
| `codeartifact_repository_name` | The name of the created CodeArtifact repository. |
| `codebuild_project_names`    | A map of repository names to CodeBuild project names. |
| `codepipeline_names`         | A map of repository names to CodePipeline names. |
