# Terraform Root Module: AWS Accounts

This Terraform configuration is a root module responsible for creating new AWS accounts within an AWS Organization. It serves as a critical step in the `infra-mgmt` pipeline, programmatically expanding the organization's footprint based on a simple input file.

## Architecture Overview

This module follows a common Terraform pattern for managing multiple similar resources. It consists of two parts:

1.  **Root Module (`/accounts`)**: This is the entry point that is executed by the `Makefile`. It acts as an orchestrator, reading a list of account definitions and using a `for_each` loop to instantiate a child module for each account.

2.  **Child Module (`/accounts/modules/account`)**: This encapsulated module contains the core logic for creating a single AWS account using the `aws_organizations_account` resource. This pattern keeps the code DRY (Don't Repeat Yourself) and makes the logic for creating one account reusable and easy to maintain.

## Workflow

This module is executed by the `make accounts-apply` command. The workflow is as follows:

1.  A Python script (`infra_mgmt.python.bin.accounts`) reads the high-level YAML configuration and generates a `accounts.json` file. This file contains the list of accounts to be created, formatted as a Terraform variables file.
2.  The `make` command invokes `terraform apply` on this root module, passing the `accounts.json` file as input.
3.  The root module iterates through the list of accounts and calls the child module for each one, creating them in AWS.
4.  The outputs of this module (like account IDs and ARNs) are written to a JSON file, which is then consumed by subsequent stages of the pipeline (like `iam-apply` and `org-apply`).

## Input Variables (Root Module)

| Name                  | Description                                                              | Type                                           | Default | Required |
| --------------------- | ------------------------------------------------------------------------ | ---------------------------------------------- | ------- | :------: |
| `aws_provider_region` | The AWS region where the AWS Organization is managed (typically `us-east-1`). | `string`                                       | n/a     |   yes    |
| `aws_profile`         | The local `~/.aws/config` profile to use for authentication.             | `string`                                       | n/a     |   yes    |
| `accounts`            | A list of account objects, each with a `name` and `email`.               | `list(object({ name = string, email = string }))` | n/a     |   yes    |

## Outputs

| Name                  | Description                                                              |
| --------------------- | ------------------------------------------------------------------------ |
| `account_ids`         | A map of account names to their newly created 12-digit AWS account IDs.  |
| `account_arns`        | A map of account names to their newly created AWS account ARNs.          |
| `assumable_role_arns` | A map of account names to the ARN of the role that can be assumed from the management account. |
| `landing_parent_ids`  | A map of account names to the ID of the parent OU or Root where the account was placed. |
