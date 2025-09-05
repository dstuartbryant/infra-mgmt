variable "aws_provider_region" {
  description = "The AWS region that changes will be made in for your AWS account."
  type        = string
}

variable "aws_profile" {
  description = "Local .aws/config profile to use."
  type        = string
}

variable "bucket_name" {
  description = "Name of bucket used for storing Terraform backend states."
  type        = string
}

variable "dynamodb_table_name" {
  description = "Name of DynamoDB table used for storing Terraform backend states."
  type        = string
}
