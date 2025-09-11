output "vpc_id" {
  description = "The ID of the VPC."
  value       = aws_vpc.main.id
}

output "subnet_id" {
  description = "The ID of the subnet."
  value       = aws_subnet.main.id
}

output "client_vpn_endpoint_id" {
  description = "The ID of the Client VPN Endpoint."
  value       = aws_ec2_client_vpn_endpoint.main.id
}
