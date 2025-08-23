variable "config" {}

# Placeholder resource for other services
resource "null_resource" "placeholder" {
  triggers = {
    project = var.config.project
    name    = var.config.name
  }
}
