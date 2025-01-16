variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "api_service_cpu" {
  description = "CPU units for API service (1024 = 1 vCPU)"
  type        = number
  default     = 256
}

variable "api_service_memory" {
  description = "Memory for API service in MB"
  type        = number
  default     = 512
}

variable "web_service_cpu" {
  description = "CPU units for web service"
  type        = number
  default     = 256
}

variable "web_service_memory" {
  description = "Memory for web service in MB"
  type        = number
  default     = 512
}

variable "api_service_count" {
  description = "Number of API service tasks to run"
  type        = number
  default     = 2
}

variable "web_service_count" {
  description = "Number of web service tasks to run"
  type        = number
  default     = 2
}

variable "db_host" {
  description = "Database host"
  type        = string
}

variable "db_password_secret_arn" {
  description = "ARN of the secret containing the database password"
  type        = string
}