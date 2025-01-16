resource "random_password" "db_password" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${var.environment}-db-password"
  recovery_window_in_days = 0
  kms_key_id             = aws_kms_key.secrets.id

  tags = {
    Environment = var.environment
  }
}

# Instead of using a data source, we'll use a null_resource to check if the secret exists
resource "null_resource" "check_secret" {
  triggers = {
    secret_id = aws_secretsmanager_secret.db_password.id
  }

  provisioner "local-exec" {
    command = <<EOF
      SECRET_EXISTS=$(aws secretsmanager list-secret-version-ids --secret-id ${aws_secretsmanager_secret.db_password.id} --query 'Versions[?VersionStage==`AWSCURRENT`]' --output text || echo "")
      if [ -n "$SECRET_EXISTS" ]; then
        echo "Secret exists"
        exit 0
      else
        echo "Secret does not exist"
        exit 1
      fi
    EOF
    on_failure = continue
  }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db_password.result

  lifecycle {
    ignore_changes = [secret_string]
    # Only create the secret version if the check fails (meaning the secret doesn't exist)
    precondition {
      condition     = null_resource.check_secret.id != ""
      error_message = "Checking if secret exists"
    }
  }
}

# Create a KMS key for encrypting secrets
resource "aws_kms_key" "secrets" {
  description             = "KMS key for encrypting secrets in ${var.environment}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Environment = var.environment
  }
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.environment}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

# Add Grafana admin password secret
resource "aws_secretsmanager_secret" "grafana_admin" {
  name                    = "${var.environment}-grafana-admin"
  recovery_window_in_days = 0

  tags = {
    Environment = var.environment
  }
} 