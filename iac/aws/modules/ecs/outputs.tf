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

output "alb_security_group_id" {
  description = "Security group ID for the ALB"
  value       = aws_security_group.alb.id
}

output "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.ecs_task_execution.arn
}

output "alb_arn_suffix" {
  description = "ARN suffix of the ALB"
  value       = aws_lb.main.arn_suffix
}

output "api_target_group_arn_suffix" {
  description = "ARN suffix of the API service target group"
  value       = aws_lb_target_group.api_service.arn_suffix
}

output "web_target_group_arn_suffix" {
  description = "ARN suffix of the web service target group"
  value       = aws_lb_target_group.web_service.arn_suffix
} 