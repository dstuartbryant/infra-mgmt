variable "vpc_cidr_block" {
  description = "The CIDR block for the VPC."
  type        = string
}

variable "subnet_cidr_block" {
  description = "The CIDR block for the private subnet."
  type        = string
}

variable "public_subnet_cidr_block" {
  description = "The CIDR block for the public subnet (for NAT Gateway)."
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

variable "split_tunnel" {
  description = "Whether to enable split-tunnel mode on the Client VPN Endpoint. When true, only traffic destined for the VPC's CIDR block will be routed through the VPN."
  type        = bool
  default     = true
}



