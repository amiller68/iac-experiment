variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "alert_email" {
  description = "Email address for alerts"
  type        = string
}

# Production configuration values
variable "api_service_cpu" {
  description = "CPU units for API service"
  type        = number
  default     = 1024
}

variable "api_service_memory" {
  description = "Memory for API service"
  type        = number
  default     = 2048
}

variable "web_service_cpu" {
  description = "CPU units for Web service"
  type        = number
  default     = 1024
}

variable "web_service_memory" {
  description = "Memory for Web service"
  type        = number
  default     = 2048
} 