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

# --- Certificate Generation (CA-based) ---

# 1. Create the Certificate Authority (CA)
resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem

  is_ca_certificate = true

  subject {
    common_name  = "${var.cert_common_name} CA"
    organization = var.cert_organization
  }

  validity_period_hours = 8760 # 1 year
  allowed_uses = [
    "cert_signing",
    "key_encipherment",
    "digital_signature",
  ]
}

# 2. Create the Server Certificate
resource "tls_private_key" "server" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "server" {
  private_key_pem = tls_private_key.server.private_key_pem

  subject {
    common_name  = var.cert_common_name
    organization = var.cert_organization
  }
}

resource "tls_locally_signed_cert" "server" {
  cert_request_pem = tls_cert_request.server.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem      = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = 4380 # 6 months
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth", # <-- This is the critical part for the server
  ]
}

# 3. Import the Server Certificate into ACM
resource "aws_acm_certificate" "server" {
  private_key      = tls_private_key.server.private_key_pem
  certificate_body = tls_locally_signed_cert.server.cert_pem
  certificate_chain = tls_self_signed_cert.ca.cert_pem
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
