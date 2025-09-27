terraform {
  required_version = ">= 1.13.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Security group to allow HTTP traffic only from the VPN
resource "aws_security_group" "webapp_sg" {
  name        = "test-webapp-sg"
  description = "Allow HTTP traffic from Client VPN"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from Client VPN"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.client_vpn_cidr, var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 instance with Nginx
resource "aws_instance" "nginx" {
  ami           = "ami-024e4b8b6ef78434a" # Pinned to a specific Amazon Linux 2 AMI for us-west-2
  instance_type = "t2.micro"
  subnet_id     = var.subnet_id
  vpc_security_group_ids = [aws_security_group.webapp_sg.id]

  # User data script to install and start Nginx
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras install nginx1 -y
              echo "<h1>Hello, World from a private instance!</h1>" > /usr/share/nginx/html/index.html
              systemctl start nginx
              systemctl enable nginx
              EOF

  tags = {
    Name = "Test-WebApp-Nginx"
  }
}