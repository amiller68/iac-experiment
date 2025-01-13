output "alb_dns_name" {
  description = "DNS name of the load balancer"
  value       = aws_lb.main.dns_name
}

output "api_service_security_group_id" {
  description = "Security group ID for the API service"
  value       = aws_security_group.api_service.id
}

output "web_service_security_group_id" {
  description = "Security group ID for the web service"
  value       = aws_security_group.web_service.id
}

output "api_service_url" {
  description = "URL for the API service"
  value       = "http://${aws_lb.main.dns_name}/api"
}

output "web_service_url" {
  description = "URL for the web service"
  value       = "http://${aws_lb.main.dns_name}"
}

output "ecs_cluster_id" {
  description = "ID of the ECS cluster"
  value       = aws_ecs_cluster.main.id
}

output "api_service_task_definition" {
  description = "Task definition ARN for the API service"
  value       = aws_ecs_task_definition.api_service.arn
}

output "web_service_task_definition" {
  description = "Task definition ARN for the web service"
  value       = aws_ecs_task_definition.web_service.arn
} 