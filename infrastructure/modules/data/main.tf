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

  tags = {
    Environment = var.environment
  }
}

# Allow access from API service
resource "aws_security_group_rule" "rds_api_ingress" {
  type                     = "ingress"
  from_port               = 5432
  to_port                 = 5432
  protocol                = "tcp"
  source_security_group_id = var.api_service_security_group_id
  security_group_id       = aws_security_group.rds.id
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier        = "${var.environment}-postgres"
  engine            = "postgres"
  engine_version    = "15"
  instance_class    = var.db_instance_class
  allocated_storage = 20

  db_name  = "messages"
  username = "postgres"
  password = var.database_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # Network settings
  network_type = "IPV4"
  publicly_accessible = false

  # Security settings
  iam_database_authentication_enabled = false
  storage_encrypted = true

  # Parameter group for allowing connections
  parameter_group_name = aws_db_parameter_group.main.name

  backup_retention_period = 7
  multi_az               = var.environment == "prod"
  skip_final_snapshot    = true

  tags = {
    Environment = var.environment
  }
}

# Create a parameter group for RDS
resource "aws_db_parameter_group" "main" {
  name   = "${var.environment}-postgres-params"
  family = "postgres15"

  parameter {
    name  = "rds.force_ssl"
    value = "0"
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

  tags = {
    Environment = var.environment
  }
}

# Allow access to EFS from web service
resource "aws_security_group_rule" "efs_web_ingress" {
  type                     = "ingress"
  from_port               = 2049
  to_port                 = 2049
  protocol                = "tcp"
  source_security_group_id = var.web_service_security_group_id
  security_group_id       = aws_security_group.efs.id
}

# SNS Topic for RDS events
resource "aws_sns_topic" "db_events" {
  name = "${var.environment}-db-events"
}

# Allow RDS to publish to SNS topic
resource "aws_sns_topic_policy" "default" {
  arn = aws_sns_topic.db_events.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRDSEvents"
        Effect = "Allow"
        Principal = {
          Service = "events.rds.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.db_events.arn
      }
    ]
  })
}

# SNS subscription to Lambda
resource "aws_sns_topic_subscription" "lambda" {
  topic_arn = aws_sns_topic.db_events.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.db_migrate.arn
}

# Create Lambda directory if it doesn't exist
resource "null_resource" "create_lambda_dir" {
  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/lambda"
  }
}

# Create Lambda package
data "archive_file" "migration_zip" {
  depends_on  = [null_resource.lambda_dependencies]
  type        = "zip"
  output_path = "${path.module}/lambda/migration.zip"
  source_dir  = "${path.module}/lambda/package"
}

# Null resource to install dependencies and prepare package
resource "null_resource" "lambda_dependencies" {
  triggers = {
    # Track Lambda source files and dependencies
    package_json = filemd5("${path.module}/lambda/package.json")
    migrate_js = filemd5("${path.module}/../../../packages/database/src/migrate.js")
    migrations_hash = sha256(join("", [
      for f in fileset("${path.module}/../../../packages/database/migrations", "*.sql") :
      filemd5("${path.module}/../../../packages/database/migrations/${f}")
    ]))
    # Include timestamp for forced updates during development
    timestamp = timestamp()
  }

  provisioner "local-exec" {
    command = <<EOF
      # Create temp directory
      rm -rf ${path.module}/lambda/package
      mkdir -p ${path.module}/lambda/package/src
      mkdir -p ${path.module}/lambda/package/migrations

      # Copy only necessary files
      cp ${path.module}/lambda/package.json ${path.module}/lambda/package/
      cp ${path.module}/../../../packages/database/src/migrate.js ${path.module}/lambda/package/src/
      cp ${path.module}/../../../packages/database/migrations/*.sql ${path.module}/lambda/package/migrations/

      # Install production dependencies
      cd ${path.module}/lambda/package && npm install --production
    EOF
  }
}

# Clean up Lambda artifacts directory
resource "null_resource" "cleanup_lambda" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = "rm -rf ${path.module}/lambda"
    when    = destroy
  }
}

# Lambda function for migrations
resource "aws_lambda_function" "db_migrate" {
  depends_on = [null_resource.lambda_dependencies]
  filename         = data.archive_file.migration_zip.output_path
  source_code_hash = data.archive_file.migration_zip.output_base64sha256
  function_name    = "${var.environment}-db-migrate"
  role            = aws_iam_role.lambda_role.arn
  handler         = "src/migrate.migrate"
  runtime         = "nodejs18.x"
  timeout         = 30
  memory_size     = 256

  environment {
    variables = {
      DB_HOST     = aws_db_instance.main.endpoint
      DB_NAME     = "messages"
      DB_USER     = "postgres"
      DB_PASSWORD = var.database_password
      ENVIRONMENT = var.environment
    }
  }

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda_sg.id]
  }
}

# CloudWatch Event to trigger migrations on deployment
resource "aws_cloudwatch_event_rule" "migration_trigger" {
  name                = "${var.environment}-db-migration-trigger"
  description         = "Triggers database migrations when files change"
  schedule_expression = "rate(1 day)"
  state              = "ENABLED"
}

resource "aws_cloudwatch_event_target" "migration_lambda" {
  rule      = aws_cloudwatch_event_rule.migration_trigger.name
  target_id = "TriggerMigrationLambda"
  arn       = aws_lambda_function.db_migrate.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.db_migrate.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.migration_trigger.arn
}

# Lambda Security Group
resource "aws_security_group" "lambda_sg" {
  name        = "${var.environment}-lambda-sg"
  description = "Security group for Lambda functions"
  vpc_id      = var.vpc_id

  # Add ingress rule if needed for debugging
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Environment = var.environment
  }
}

# Make sure RDS security group allows access from Lambda
resource "aws_security_group_rule" "rds_lambda_ingress" {
  type                     = "ingress"
  from_port               = 5432
  to_port                 = 5432
  protocol                = "tcp"
  source_security_group_id = aws_security_group.lambda_sg.id
  security_group_id       = aws_security_group.rds.id
}

# IAM role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${var.environment}-lambda-migration-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for Lambda
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.environment}-lambda-migration-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      }
    ]
  })
}

# Update Lambda function to write to SSM
resource "aws_iam_role_policy" "lambda_ssm" {
  name = "${var.environment}-lambda-ssm-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:PutParameter"
        ]
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${var.environment}/migration-status"
      }
    ]
  })
}

# Get current region and account ID
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# VPC Endpoint for SSM
resource "aws_vpc_endpoint" "ssm" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.ssm"
  vpc_endpoint_type = "Interface"
  
  subnet_ids = var.private_subnet_ids
  security_group_ids = [aws_security_group.lambda_sg.id]

  private_dns_enabled = true

  tags = {
    Environment = var.environment
  }
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.environment}-db-migrate"
  retention_in_days = 14

  tags = {
    Environment = var.environment
  }
}