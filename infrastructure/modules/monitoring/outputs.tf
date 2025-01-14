output "prometheus_security_group_id" {
  description = "Security group ID for Prometheus"
  value       = aws_security_group.monitoring.id
}

output "grafana_security_group_id" {
  description = "Security group ID for Grafana"
  value       = aws_security_group.monitoring.id
} 