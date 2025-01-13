environment = "staging"
aws_region  = "us-east-1"
vpc_cidr    = "10.0.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b"]

# These values should be provided in a separate secrets.tfvars file
# database_password      = "your-secure-password"
# grafana_admin_password = "your-secure-password"
# alert_email           = "your-email@example.com" 