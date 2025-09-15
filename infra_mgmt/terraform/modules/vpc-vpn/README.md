# Terraform Module: VPC and Client VPN (Certificate-Based)

This module provisions a foundational networking stack for an AWS account. It creates a Virtual Private Cloud (VPC) with a single subnet and deploys an AWS Client VPN Endpoint configured to use mutual certificate-based authentication.

## Architecture Overview

This module provides a secure, private network environment and the core components for a robust, certificate-based access method.

1.  **VPC & Subnet**: A standard VPC is created to house AWS resources, with a single subnet provisioned within it.
2.  **Internal Certificate Authority (CA)**: The module creates a self-signed Certificate Authority (CA) using the `tls` provider. This CA is used exclusively for signing the server and client certificates.
3.  **Server Certificate**: A server-side certificate is generated, signed by the internal CA, and uploaded to AWS Certificate Manager (ACM).
4.  **Client VPN Endpoint**: An AWS Client VPN Endpoint is deployed and associated with the subnet. It is configured for mutual certificate authentication, requiring both the server and the connecting client to present a valid, trusted certificate.
5.  **Network Configuration**: The module creates the necessary network association, authorization rule, and route to allow authenticated VPN clients to access all resources within the VPC.

## Client Certificate Management

This module is designed to be used as part of a larger automation framework. It creates and outputs the Certificate Authority (CA) certificate and private key, which are then intended to be used by a higher-level process to automatically generate client certificates.

**Issuing and managing client certificates is not handled directly within this module.**

In the context of the `infra-mgmt` project this module was built for, client certificate generation is fully automated based on a central user configuration file. Please refer to the main project `README.md` for detailed instructions on how to grant users VPN access and how the certificate distribution process works.

## Input Variables

| Name                                  | Description                                                              | Type     | Default         | Required |
| ------------------------------------- | ------------------------------------------------------------------------ | -------- | --------------- | :------: |
| `vpc_cidr_block`                      | The CIDR block for the VPC. Must not overlap with other networks.        | `string` | n/a             |   yes    |
| `subnet_cidr_block`                   | The CIDR block for the subnet. Must be a subset of the VPC's CIDR block. | `string` | n/a             |   yes    |
| `client_vpn_endpoint_client_cidr_block` | The CIDR block for the Client VPN client IP pool. **Must not** overlap with the VPC CIDR. | `string` | n/a             |   yes    |
| `cert_common_name`                    | The common name for the server-side certificate.                         | `string` | `"example.com"` |    no    |
| `cert_organization`                   | The organization name for the server-side certificate.                   | `string` | `"Example, Inc."` |    no    |

## Outputs

| Name                   | Description                                                                 |
| ---------------------- | --------------------------------------------------------------------------- |
| `vpc_id`               | The ID of the created VPC.                                                  |
| `subnet_id`            | The ID of the created subnet.                                               |
| `client_vpn_endpoint_id` | The ID of the Client VPN Endpoint.                                          |
| `server_certificate_pem` | The PEM-encoded server certificate for the Client VPN.                      |
| `ca_certificate_pem`   | The PEM-encoded CA certificate. Needed for signing and client configuration. |
| `ca_private_key_pem`   | The PEM-encoded CA private key. **Handle with care.**                       |
