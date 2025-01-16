variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "api_service_security_group_id" {
  description = "Security group ID for the API service"
  type        = string
}

variable "web_service_security_group_id" {
  description = "Security group ID for the web service"
  type        = string
}

variable "db_password_secret_arn" {
  description = "ARN of the secret containing the database password"
  type        = string
}

variable "kms_key_id" {
  description = "KMS key ID for RDS encryption"
  type        = string
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "migration_status_param_name" {
  description = "Name of the SSM parameter for tracking migration status"
  type        = string
} 