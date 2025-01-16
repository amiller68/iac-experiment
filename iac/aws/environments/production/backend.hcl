bucket         = "iac-experiment-tf-state"
key            = "environments/production/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "terraform-state-lock"
encrypt        = true 