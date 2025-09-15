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

output "client_vpn_cidr" {
  description = "The CIDR block for the Client VPN client IP pool."
  value       = var.client_vpn_endpoint_client_cidr_block
}

output "required_permission_set_statements" {
  description = "A list of IAM policy statements that should be applied to the developer permission set."
  value = [
    {
      Sid    = "AllowVPNConfigDownload",
      Effect = "Allow",
      Action = [
        "ec2:DescribeClientVpnEndpoints",
        "ec2:ExportClientVpnClientConfiguration"
      ],
      Resource = "*"
    }
  ]
}

output "server_certificate_pem" {
  description = "The PEM-encoded server certificate for the Client VPN."
  value       = tls_locally_signed_cert.server.cert_pem
  sensitive   = true
}