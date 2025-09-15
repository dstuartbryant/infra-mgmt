# Infra-Mgmt

An automated framework for bootstrapping and managing a multi-account AWS Organization using a combination of Python and Terraform.

This project is designed to create a secure, scalable, and repeatable AWS environment from the ground up. It uses a central YAML file for high-level configuration and Python scripts to dynamically generate Terraform code, which is then applied in a staged manner via a `Makefile`.

## Core Features

- **Automated AWS Account Creation**: Defines new AWS accounts within an AWS Organization from a simple configuration file.
- **Centralized IAM Management**: Sets up initial IAM users, groups, and permissions in the management account.
- **Dynamic Terraform Generation**: Overcomes Terraform's limitations with dynamic providers by generating distinct, isolated root modules for each AWS account.
- **Per-Account Infrastructure Deployment**: Deploys standardized infrastructure to each account, including:
  - A secure VPC with a private subnet.
  - An AWS Client VPN endpoint using mutual certificate authentication.
  - A foundational CICD pipeline with CodeBuild and CodeArtifact.
- **Automated VPN Client Certificate Management**: Automatically generates, manages, and stores client certificates for authorized users, tied directly to the central user configuration.

## Architectural Approach

A core challenge in Terraform is dynamically configuring `provider` blocks, which is necessary when the resources you're creating (like AWS accounts) are themselves the targets for later configuration.

This project solves this by using Python as a pre-processor for Terraform. The `Makefile` orchestrates a workflow where Python scripts read a high-level YAML configuration and generate distinct Terraform root modules for each AWS account in the `.build/` directory. This approach ensures that each account's infrastructure is managed in a completely isolated state, preventing configuration drift or input variable conflicts.

## Prerequisites

Ensure your local AWS CLI is configured with credentials for the AWS management account. The scripts and Terraform commands will use these credentials to operate.

## Usage Workflow

The entire workflow is managed through the `Makefile`. The targets are designed to be run sequentially.

1.  **`make bootstrap`**
    - Creates the S3 bucket and DynamoDB table that will serve as the Terraform remote state backend.

2.  **`make backend-config`**
    - Generates the `backend.hcl` file with the outputs from the bootstrap step. All subsequent Terraform modules will use this file to connect to the remote state backend.

3.  **`make accounts-apply`**
    - Reads the project definitions and creates the corresponding AWS accounts within your AWS Organization.

4.  **`make iam-apply`**
    - Creates the initial set of IAM users and groups in the management account.

5.  **`make org-apply`**
    - This is the main step. It iterates through each AWS account and applies the Terraform configuration to deploy the VPC, Client VPN, and CICD pipeline.
    - **This step also automatically generates VPN client certificates** for any user configured with `vpn_access: true`.

You can also run `make all` to execute the entire sequence from `bootstrap` to `org-apply`.

## Configuration

All user-facing configuration is managed via a single YAML file: `proto_configs/config.yaml`. This file defines:
- Global settings and AWS profiles.
- The AWS accounts to be created (`projects`).
- Network configurations (VPC and VPN CIDR blocks).
- IAM users, groups, and their associations to accounts.

## VPN Access and Client Certificates

The system uses a robust, automated process for managing VPN access via client certificates.

### Granting VPN Access

To grant a user VPN access to the accounts their groups are assigned to, simply add the `vpn_access: true` flag to their user definition in `proto_configs/config.yaml`:

```yaml
unclass_users:
  - display_name: "Jane Doe"
    user_name: "jane.doe"
    name:
      given_name: "Jane"
      family_name: "Doe"
    email: "jane.doe@example.com"
    groups:
      - "unclass_developer_testProjectA"
    vpn_access: true # <-- Add this line
```

### Certificate Generation and Distribution

When you run `make org-apply`, the system automatically generates the necessary certificate files for any user with `vpn_access: true`.

-   **Location**: The generated files are stored locally in the `.client_vpn_configs/` directory, organized by account alias (e.g., `.client_vpn_configs/testProjectA_unclassified/`). This directory is ignored by Git.
-   **Files per User**: For each user, two files are created: `jane.doe.key` (the private key) and `jane.doe.crt` (the signed certificate).

**To configure a user's AWS VPN Client, you must securely provide them with three items:**

1.  Their private key (`<user_name>.key`).
2.  Their signed certificate (`<user_name>.crt`).
3.  The Certificate Authority (CA) certificate. This is the same for everyone in an account. You can get its content from the Terraform output of the account's `org-apply` step, or find it in the `.terraform/` state directory.

These files are then used to create a connection profile in the AWS VPN Client software.