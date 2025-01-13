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

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group ID of the ALB"
  type        = string
}

variable "ecs_cluster_id" {
  description = "ID of the ECS cluster"
  type        = string
}

variable "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
}

variable "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  type        = string
}

variable "prometheus_cpu" {
  description = "CPU units for Prometheus"
  type        = number
  default     = 512
}

variable "prometheus_memory" {
  description = "Memory for Prometheus in MB"
  type        = number
  default     = 1024
}

variable "grafana_cpu" {
  description = "CPU units for Grafana"
  type        = number
  default     = 256
}

variable "grafana_memory" {
  description = "Memory for Grafana in MB"
  type        = number
  default     = 512
}

variable "grafana_admin_password" {
  description = "Admin password for Grafana"
  type        = string
  sensitive   = true
}

variable "efs_id" {
  description = "ID of the EFS filesystem"
  type        = string
}

variable "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  type        = string
}

variable "monitoring_ami" {
  description = "AMI ID for monitoring instance"
  type        = string
  default     = "ami-0cff7528ff583bf9a"  # Amazon Linux 2 AMI
}

variable "monitoring_instance_type" {
  description = "Instance type for monitoring"
  type        = string
  default     = "t3.small"
}

variable "monitoring_volume_size" {
  description = "Size of the monitoring data volume in GB"
  type        = string
  default     = "100"
} 