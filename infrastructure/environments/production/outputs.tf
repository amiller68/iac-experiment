output "web_service_url" {
  description = "URL of the web service"
  value       = module.infrastructure.web_service_url
}

output "api_service_url" {
  description = "URL of the API service"
  value       = module.infrastructure.api_service_url
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.infrastructure.vpc_id
} 