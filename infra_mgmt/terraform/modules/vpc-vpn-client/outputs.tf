output "client_key_path" {
  description = "The path to the generated client private key file."
  value       = local_sensitive_file.client_key.filename
}

output "client_cert_path" {
  description = "The path to the generated client certificate file."
  value       = local_file.client_crt.filename
}

output "ca_cert_pem" {
  description = "The CA certificate, useful for inclusion in VPN profiles."
  value       = var.ca_certificate_pem
  sensitive   = true
}
