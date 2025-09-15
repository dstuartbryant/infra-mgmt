variable "vpc_id" {
  description = "The ID of the VPC where the web app will be deployed."
  type        = string
}

variable "subnet_id" {
  description = "The ID of the subnet where the web app will be deployed."
  type        = string
}

variable "client_vpn_cidr" {
  description = "The CIDR block of the Client VPN."
  type        = string
}

variable "vpc_cidr" {
  description = "The CIDR block of the VPC."
  type        = string
}
