# infra-mgmt

A Terraform project for managing a multi-account AWS setup.

- bootstrap: Creates the Terraform state backend (S3/DynamoDB).
- configs: Holds YAML definitions for projects, services, and user access.
- org: The main Terraform code that builds AWS accounts and environments from the YAML configs.


## Reasoning Notes
1. Terraform does not let you dynamically configure provider blocks, which is problematic if you want to accommodate dynamically creating, and then separately managing, multiple AWS accounts. Due to this and a desire to surface up a minimal collection of user interfacing tools for managing multiple AWS accounts, it became necessary to dynamically generate organizational "org" level Terraform configs to maintain harmony with provider and input configurations. Of particular concern was ensuring Terraform inputs for different accounts did not get mixed, so, each project/classification, i.e., each AWS account, has it's own "root" folder generated in the build directory.