# Infra-Mgmt

An automated framework for bootstrapping and managing a multi-account AWS Organization using a combination of Python and Terraform.

This project is designed to create a secure, scalable, and repeatable AWS environment from the ground up. It uses YAML files for high-level configuration and Python scripts to dynamically generate Terraform code, which is then applied in a staged manner via a `Makefile`.

## Core Features

- **Automated AWS Account Creation**: Defines new AWS accounts within an AWS Organization from a simple configuration file.
- **Centralized IAM Management**: Sets up initial IAM users, groups, and permissions in the management account.
- **Dynamic Terraform Generation**: Overcomes Terraform's limitations with dynamic providers by generating distinct, isolated root modules for each AWS account.
- **Per-Account Infrastructure Deployment**: Deploys standardized infrastructure to each account, including:
  - A secure VPC with a private subnet.
  - An AWS Client VPN endpoint configured for SSO authentication.
  - A foundational CICD pipeline with CodeBuild and CodeArtifact.

## Architectural Approach

A core challenge in Terraform is dynamically configuring `provider` blocks, which is necessary when the resources you're creating (like AWS accounts) are themselves the targets for later configuration.

This project solves this by using Python as a pre-processor for Terraform. The `Makefile` orchestrates a workflow where Python scripts read high-level YAML configurations and generate distinct Terraform root modules for each AWS account in the `.build/` directory. This approach ensures that each account's infrastructure is managed in a completely isolated state, preventing configuration drift or input variable conflicts.

## Prerequisites

Before running any commands, you must complete the following setup steps.

1.  **AWS Credentials**: Ensure your local AWS CLI is configured with credentials for the AWS management account. The scripts and Terraform commands will use these credentials to operate.

2.  **IAM Identity Center (SSO) Application**: The Client VPN authentication relies on a manually configured SAML application in AWS SSO. This step cannot be automated via Terraform.
    - In the AWS Console, navigate to **IAM Identity Center**.
    - Go to **Applications** -> **Add application**.
    - Select **"I have an application I want to setup"**.
    - For the application type, select **SAML 2.0**.
    - When prompted, select **"Manually type your metadata values"** and input the following:
      - **Application ACS URL**: `http://127.0.0.1:35001`
      - **Application SAML audience**: `urn:amazon:webservices:clientvpn`
    - After creating the application, go to its **Configuration** page (you may need to click "Actions" -> "Edit configuration").
    - Download the **"IAM Identity Center SAML metadata file"**.
    - **Crucially, save this file to the following path:** `proto_configs/sso_app_metadata.xml`. The Terraform automation depends on this exact file path.

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

You can also run `make all` to execute the entire sequence from `bootstrap` to `org-apply`.

## Configuration

All user-facing configuration is managed via YAML files in the `proto_configs/` directory.

-   **`config.yaml`**: Defines global settings, AWS profiles, and IAM users/groups.
-   **`projects.yaml`**: Defines the AWS accounts to be created and their specific network configurations (VPC and VPN CIDR blocks).
