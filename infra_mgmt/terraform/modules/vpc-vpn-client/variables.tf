variable "user_name" {
  description = "The name of the user for whom the certificate is being generated."
  type        = string
}

variable "organization" {
  description = "The organization name to embed in the certificate."
  type        = string
}

variable "ca_private_key_pem" {
  description = "The PEM-encoded private key of the Certificate Authority."
  type        = string
  sensitive   = true
}

variable "ca_certificate_pem" {
  description = "The PEM-encoded certificate of the Certificate Authority."
  type        = string
  sensitive   = true
}

variable "output_path" {
  description = "The local directory path to save the generated key and certificate files."
  type        = string
}
