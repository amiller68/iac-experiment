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

variable "database_password" {
  description = "Password for RDS instance"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
} 