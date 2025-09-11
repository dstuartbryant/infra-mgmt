# Terraform Module: Backend

This module is the foundational first step for the entire `infra-mgmt` project. It provisions the necessary AWS infrastructure to support a robust and secure Terraform remote state backend.

Using a remote backend is a best practice for any team-based or automated Terraform workflow. It ensures that the state file is stored reliably, is accessible to all authorized users and processes, and is protected against corruption or accidental deletion.

## Architecture Overview

This module creates two core resources in the AWS management account:

1.  **S3 Bucket**: A secure S3 bucket is created to store the Terraform state files (`.tfstate`). The bucket is configured with:
    -   **Versioning**: To keep a history of all state file changes, allowing for recovery from errors.
    -   **Server-Side Encryption**: To ensure the state file is encrypted at rest.
    -   **Prevent Destroy Lifecycle**: To protect the bucket from accidental deletion.

2.  **DynamoDB Table**: A DynamoDB table is created to handle Terraform's state locking mechanism. When a Terraform command that modifies state (like `apply` or `destroy`) is run, it places a lock in this table. This prevents other users from running commands at the same time, which could corrupt the state file.

## Workflow

This module is intended to be run once at the very beginning of the project setup. The `Makefile` orchestrates this via the `make bootstrap` command.

The outputs of this module (the bucket name, table name, region, and profile) are then used to generate the `backend.hcl` file, which configures all other Terraform modules in this project to use this newly created remote backend.

## Input Variables

| Name                  | Description                                                              | Type     | Default | Required |
| --------------------- | ------------------------------------------------------------------------ | -------- | ------- | :------: |
| `aws_provider_region` | The AWS region where the backend resources will be created.              | `string` | n/a     |   yes    |
| `aws_profile`         | The local `~/.aws/config` profile to use for authenticating the command. | `string` | n/a     |   yes    |
| `bucket_name`         | The globally unique name for the S3 bucket that will store the state.    | `string` | n/a     |   yes    |
| `dynamodb_table_name` | The name for the DynamoDB table that will handle state locking.          | `string` | n/a     |   yes    |

## Outputs

| Name                | Description                                                              |
| ------------------- | ------------------------------------------------------------------------ |
| `s3_bucket_name`    | The name of the created S3 bucket.                                       |
| `dynamodb_table_name` | The name of the created DynamoDB table.                                  |
| `region`            | The AWS region where the resources were created.                         |
| `profile`           | The AWS profile used to create the resources.                            |
