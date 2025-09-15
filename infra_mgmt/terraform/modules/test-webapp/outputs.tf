output "webapp_private_ip" {
  description = "The private IP address of the test web app EC2 instance."
  value       = aws_instance.nginx.private_ip
}

output "webapp_instance_id" {
  description = "The ID of the test web app EC2 instance."
  value       = aws_instance.nginx.id
}