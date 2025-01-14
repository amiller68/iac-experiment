output "vpc_id" {
  value = module.networking.vpc_id
}

output "api_service_url" {
  value = module.ecs.api_service_url
}

output "web_service_url" {
  value = module.ecs.web_service_url
}

output "rds_endpoint" {
  value     = module.data.rds_endpoint
  sensitive = true
}

output "grafana_security_group_id" {
  value = module.monitoring.grafana_security_group_id
}

output "prometheus_security_group_id" {
  value = module.monitoring.prometheus_security_group_id
} 