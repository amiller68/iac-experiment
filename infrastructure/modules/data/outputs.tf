output "rds_endpoint" {
  value = aws_db_instance.main.endpoint
}

output "efs_id" {
  value = aws_efs_file_system.main.id
}

output "rds_security_group_id" {
  value = aws_security_group.rds.id
}

output "efs_security_group_id" {
  value = aws_security_group.efs.id
} 