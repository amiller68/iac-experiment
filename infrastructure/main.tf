provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "microservices-infrastructure"
      ManagedBy   = "terraform"
    }
  }
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}


# Networking
module "networking" {
  source = "./modules/networking"

  environment        = var.environment
  aws_region        = var.aws_region
  vpc_cidr          = var.vpc_cidr
  availability_zones = var.availability_zones
}

# Data Layer
module "data" {
  source = "./modules/data"

  environment                  = var.environment
  vpc_id                      = module.networking.vpc_id
  private_subnet_ids          = module.networking.private_subnet_ids
  api_service_security_group_id = module.ecs.api_service_security_group_id
  web_service_security_group_id = module.ecs.web_service_security_group_id
  database_password           = var.database_password
}

# ECS
module "ecs" {
  source = "./modules/ecs"

  environment        = var.environment
  aws_region        = var.aws_region
  vpc_id            = module.networking.vpc_id
  public_subnet_ids = module.networking.public_subnet_ids
  private_subnet_ids = module.networking.private_subnet_ids
  
  db_host          = module.data.rds_endpoint
  database_password = var.database_password
  efs_id           = module.data.efs_id

  api_service_cpu    = var.api_service_cpu
  api_service_memory = var.api_service_memory
  web_service_cpu    = var.web_service_cpu
  web_service_memory = var.web_service_memory
}

# Monitoring
module "monitoring" {
  source = "./modules/monitoring"

  environment                = var.environment
  aws_region                = var.aws_region
  vpc_id                    = module.networking.vpc_id
  private_subnet_ids        = module.networking.private_subnet_ids
  alb_security_group_id     = module.ecs.alb_security_group_id
  ecs_cluster_id           = module.ecs.ecs_cluster_id
  ecs_cluster_name         = "${var.environment}-cluster"
  ecs_task_execution_role_arn = module.ecs.ecs_task_execution_role_arn
  efs_id                   = module.data.efs_id
  grafana_admin_password   = var.grafana_admin_password
  sns_topic_arn           = aws_sns_topic.alerts.arn
}

# SNS Topic for Alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.environment}-alerts"
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
} 