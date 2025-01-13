# RDS Subnet Group
resource "aws_db_subnet_group" "main" {
  name        = "${var.environment}-db-subnet-group"
  description = "Database subnet group for ${var.environment}"
  subnet_ids  = var.private_subnet_ids

  tags = {
    Environment = var.environment
  }
}

# RDS Security Group
resource "aws_security_group" "rds" {
  name        = "${var.environment}-rds-sg"
  description = "Security group for RDS instance"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.api_service_security_group_id]
  }

  tags = {
    Environment = var.environment
  }
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier        = "${var.environment}-postgres"
  engine            = "postgres"
  engine_version    = "13.7"
  instance_class    = var.db_instance_class
  allocated_storage = 20

  db_name  = "messages"
  username = "postgres"
  password = var.database_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  backup_retention_period = 7
  multi_az               = var.environment == "prod"
  skip_final_snapshot    = true

  tags = {
    Environment = var.environment
  }
}

# EFS File System
resource "aws_efs_file_system" "main" {
  creation_token = "${var.environment}-efs"
  encrypted      = true

  tags = {
    Name        = "${var.environment}-efs"
    Environment = var.environment
  }
}

# EFS Mount Targets
resource "aws_efs_mount_target" "main" {
  count           = length(var.private_subnet_ids)
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

# EFS Security Group
resource "aws_security_group" "efs" {
  name        = "${var.environment}-efs-sg"
  description = "Security group for EFS mount targets"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [var.web_service_security_group_id]
  }

  tags = {
    Environment = var.environment
  }
} 