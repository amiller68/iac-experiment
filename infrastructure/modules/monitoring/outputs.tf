output "prometheus_security_group_id" {
  description = "Security group ID for Prometheus"
  value       = aws_security_group.monitoring.id
}

output "grafana_security_group_id" {
  description = "Security group ID for Grafana"
  value       = aws_security_group.monitoring.id
}

output "prometheus_task_definition" {
  description = "Task definition ARN for Prometheus"
  value       = aws_ecs_task_definition.prometheus.arn
}

output "grafana_task_definition" {
  description = "Task definition ARN for Grafana"
  value       = aws_ecs_task_definition.grafana.arn
}

output "api_service_log_group" {
  description = "CloudWatch log group for API service"
  value       = aws_cloudwatch_log_group.api_service.name
}

output "web_service_log_group" {
  description = "CloudWatch log group for web service"
  value       = aws_cloudwatch_log_group.web_service.name
}

output "api_service_alarm_arn" {
  description = "ARN of the API service error alarm"
  value       = aws_cloudwatch_metric_alarm.api_service_errors.arn
}

output "web_service_alarm_arn" {
  description = "ARN of the web service error alarm"
  value       = aws_cloudwatch_metric_alarm.web_service_errors.arn
} 