# infra-mgmt

A Terraform project for managing a multi-account AWS setup.

- bootstrap: Creates the Terraform state backend (S3/DynamoDB).
- configs: Holds YAML definitions for projects, services, and user access.
- org: The main Terraform code that builds AWS accounts and environments from the YAML configs.

