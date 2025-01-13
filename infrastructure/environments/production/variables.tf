variable "database_password" {
  description = "Password for RDS instance"
  type        = string
  sensitive   = true
}

variable "grafana_admin_password" {
  description = "Admin password for Grafana"
  type        = string
  sensitive   = true
}

variable "alert_email" {
  description = "Email address for alerts"
  type        = string
} 