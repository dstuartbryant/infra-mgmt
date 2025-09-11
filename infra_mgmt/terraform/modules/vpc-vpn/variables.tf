variable "vpc_cidr_block" {
  description = "The CIDR block for the VPC."
  type        = string
}

variable "subnet_cidr_block" {
  description = "The CIDR block for the subnet."
  type        = string
}

variable "client_vpn_endpoint_client_cidr_block" {
  description = "The CIDR block for the Client VPN Endpoint."
  type        = string
}

variable "cert_common_name" {
  description = "The common name for the self-signed certificate."
  type        = string
}

variable "cert_organization" {
  description = "The organization name for the self-signed certificate."
  type        = string
}
