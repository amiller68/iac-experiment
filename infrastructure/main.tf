provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "microservices-infrastructure"
      ManagedBy   = "terraform"
      Owner       = "DevOps"
      CostCenter  = "Infrastructure"
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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
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

# Secrets Management
module "secrets" {
  source = "./modules/secrets"

  environment            = var.environment
}

# Data Layer
module "data" {
  source = "./modules/data"

  environment                    = var.environment
  vpc_id                        = module.networking.vpc_id
  private_subnet_ids            = module.networking.private_subnet_ids
  api_service_security_group_id = module.ecs.api_service_security_group_id
  web_service_security_group_id = module.ecs.web_service_security_group_id
  kms_key_id                   = module.secrets.kms_key_id
  db_password_secret_arn       = module.secrets.db_password_secret_arn
}

# ECS
module "ecs" {
  source = "./modules/ecs"

  environment        = var.environment
  aws_region        = var.aws_region
  vpc_id            = module.networking.vpc_id
  public_subnet_ids = module.networking.public_subnet_ids
  private_subnet_ids = module.networking.private_subnet_ids
  
  db_host               = module.data.rds_endpoint
  db_password_secret_arn = module.secrets.db_password_secret_arn

  api_service_cpu    = var.api_service_cpu
  api_service_memory = var.api_service_memory
  web_service_cpu    = var.web_service_cpu
  web_service_memory = var.web_service_memory
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