# 1. Generate a private key for the user.
# This resource is idempotent; Terraform stores the generated key in its state
# and will not change it on subsequent applies unless the resource is tainted or destroyed.
resource "tls_private_key" "client" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# 2. Create a certificate signing request (CSR) for the user.
resource "tls_cert_request" "client" {
  private_key_pem = tls_private_key.client.private_key_pem

  subject {
    common_name  = var.user_name
    organization = var.organization
  }
}

# 3. Sign the user's CSR with the CA passed in from the vpc-vpn module.
resource "tls_locally_signed_cert" "client" {
  cert_request_pem = tls_cert_request.client.cert_request_pem
  ca_private_key_pem = var.ca_private_key_pem
  ca_cert_pem      = var.ca_certificate_pem

  validity_period_hours = 8760 # 1 year
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "client_auth", # This is the critical part for a client certificate
  ]
}

# 4. Ensure the output directory exists.
resource "local_file" "ensure_dir" {
  content  = "# This file ensures the directory exists for client certs."
  filename = "${var.output_path}/.placeholder"
}

# 5. Save the user's private key and signed certificate to the local filesystem.
resource "local_sensitive_file" "client_key" {
  content    = tls_private_key.client.private_key_pem
  filename   = "${var.output_path}/${var.user_name}.key"
  depends_on = [local_file.ensure_dir]
}

resource "local_file" "client_crt" {
  content    = tls_locally_signed_cert.client.cert_pem
  filename   = "${var.output_path}/${var.user_name}.crt"
  depends_on = [local_file.ensure_dir]
}
