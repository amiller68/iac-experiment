terraform {
  backend "s3" {
    bucket         = "iac-experiment-tf-state"
    key            = "environments/production/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

module "infrastructure" {
  source = "../../"
  
  environment = "production"
  aws_region  = "us-east-1"
  vpc_cidr    = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

  alert_email           = var.alert_email

  api_service_cpu     = 1024
  api_service_memory  = 2048
  web_service_cpu     = 1024
  web_service_memory  = 2048
} 