output "db_password_secret_arn" {
  value = aws_secretsmanager_secret.db_password.arn
}

output "kms_key_id" {
  value = aws_kms_key.secrets.arn
}

output "grafana_admin_secret_arn" {
  value = aws_secretsmanager_secret.grafana_admin.arn
} 