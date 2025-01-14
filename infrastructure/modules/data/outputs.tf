output "rds_endpoint" {
  value = aws_db_instance.main.address
}

output "rds_security_group_id" {
  value = aws_security_group.rds.id
}

output "lambda_environment_variables" {
  value = aws_lambda_function.db_migrate.environment
  sensitive = true
} 