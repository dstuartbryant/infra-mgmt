terraform {
  required_version = ">= 1.13.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr_block
}


resource "aws_subnet" "main" {
  vpc_id     = aws_vpc.main.id
  cidr_block = var.subnet_cidr_block
}

resource "tls_private_key" "server" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "server" {
  private_key_pem = tls_private_key.server.private_key_pem

  subject {
    common_name  = var.cert_common_name
    organization = var.cert_organization
  }

  validity_period_hours = 12
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "server" {
  private_key      = tls_private_key.server.private_key_pem
  certificate_body = tls_self_signed_cert.server.cert_pem
}

data "local_file" "sso_app_metadata" {
  filename = "${path.root}/../../../../../proto_configs/sso_app_metadata.xml"
}

resource "aws_iam_saml_provider" "sso" {
  name                   = "AWSSSO"
  saml_metadata_document = data.local_file.sso_app_metadata.content
}

resource "aws_ec2_client_vpn_endpoint" "main" {
  description            = "Client VPN endpoint"
  client_cidr_block      = var.client_vpn_endpoint_client_cidr_block
  server_certificate_arn = aws_acm_certificate.server.arn

  authentication_options {
    type                           = "federated-authentication"
    saml_provider_arn              = aws_iam_saml_provider.sso.arn
    self_service_saml_provider_arn = aws_iam_saml_provider.sso.arn
  }

  connection_log_options {
    enabled = false
  }
}

resource "aws_ec2_client_vpn_network_association" "main" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.main.id
  subnet_id              = aws_subnet.main.id
}

resource "aws_ec2_client_vpn_authorization_rule" "main" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.main.id
  target_network_cidr    = aws_vpc.main.cidr_block
  authorize_all_groups   = true
}

resource "aws_ec2_client_vpn_route" "main" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.main.id
  destination_cidr_block = "0.0.0.0/0"
  target_vpc_subnet_id   = aws_subnet.main.id

  timeouts {
    create = "10m"
  }
}
