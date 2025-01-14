variable "environment" {
  description = "Environment name"
  type        = string
}

variable "database_password" {
  description = "Database password to store in secrets manager"
  type        = string
  sensitive   = true
}

variable "grafana_admin_password" {
  description = "Admin password for Grafana"
  type        = string
  sensitive   = true
} 