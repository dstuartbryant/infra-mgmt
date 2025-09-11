# Terraform Module: VPC and Client VPN

This module provisions a foundational networking stack for an AWS account. It creates a Virtual Private Cloud (VPC) with a single subnet and deploys an AWS Client VPN Endpoint configured to use IAM Identity Center (SSO) for federated authentication.

## Architecture Overview

This module provides a secure, private network environment and a way for authenticated users to access it.

1.  **VPC & Subnet**: A standard VPC is created to house your AWS resources. A single subnet is provisioned within the VPC.
2.  **IAM SAML Provider**: An IAM SAML provider is created within the account. It is configured using a metadata file exported from a manually-created SAML application in IAM Identity Center. This establishes the trust relationship required for SSO authentication.
3.  **Client VPN Endpoint**: An AWS Client VPN Endpoint is deployed and associated with the subnet. It is configured to use the IAM SAML provider, forcing users to authenticate via the SSO login flow before they can connect to the VPN.
4.  **Self-Signed Certificate**: For the VPN's server-side certificate, the module generates a self-signed TLS certificate and uploads it to AWS Certificate Manager (ACM).

## Prerequisite: SSO Application Metadata

This module **requires** a SAML metadata file to be present in the project directory. This file is generated from a custom SAML 2.0 application that you must create manually in the AWS IAM Identity Center console.

**File Path**: The module expects the file to be located at `proto_configs/sso_app_metadata.xml` relative to the project root.

Please see the main project `README.md` for detailed instructions on how to create the SAML application and download this file.

## Resources Created

-   **VPC**: The main virtual private cloud.
-   **Subnet**: A single subnet within the VPC.
-   **IAM SAML Provider**: Establishes trust with your IAM Identity Center application.
-   **ACM Certificate**: A self-signed server certificate for the VPN endpoint.
-   **EC2 Client VPN Endpoint**: The managed VPN service.
-   **Network Association**: Links the VPN endpoint to the subnet.
-   **Authorization Rule**: Authorizes all authenticated users to access the entire VPC.
-   **Route**: A default route to allow VPN clients to access all destinations (0.0.0.0/0) through the VPC.

## Input Variables

| Name                                  | Description                                                              | Type     | Default         | Required |
| ------------------------------------- | ------------------------------------------------------------------------ | -------- | --------------- | :------: |
| `vpc_cidr_block`                      | The CIDR block for the VPC. Must not overlap with other networks.        | `string` | n/a             |   yes    |
| `subnet_cidr_block`                   | The CIDR block for the subnet. Must be a subset of the VPC's CIDR block. | `string` | n/a             |   yes    |
| `client_vpn_endpoint_client_cidr_block` | The CIDR block for the Client VPN client IP pool. **Must not** overlap with the VPC CIDR. | `string` | n/a             |   yes    |
| `cert_common_name`                    | The common name for the self-signed certificate.                         | `string` | `"example.com"` |    no    |
| `cert_organization`                   | The organization name for the self-signed certificate.                   | `string` | `"Example, Inc."` |    no    |

## Outputs

| Name                   | Description                        |
| ---------------------- | ---------------------------------- |
| `vpc_id`               | The ID of the created VPC.         |
| `subnet_id`            | The ID of the created subnet.      |
| `client_vpn_endpoint_id` | The ID of the Client VPN Endpoint. |
