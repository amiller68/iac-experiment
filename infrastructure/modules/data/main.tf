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

  # Add ingress rules inline instead of separate resources
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.api_service_security_group_id]
    description     = "Allow PostgreSQL access from API service"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Environment = var.environment
  }
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
  manage_master_user_password = true
  master_user_secret_kms_key_id = var.kms_key_id

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # Network settings
  network_type = "IPV4"
  publicly_accessible = false

  # Security settings
  iam_database_authentication_enabled = false
  storage_encrypted = true
  kms_key_id       = var.kms_key_id

  # Parameter group for allowing connections
  parameter_group_name = aws_db_parameter_group.main.name

  backup_retention_period = 7
  multi_az               = var.environment == "production"
  skip_final_snapshot    = true

  performance_insights_enabled = true
  performance_insights_retention_period = 7  # days

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

# Install dependencies for Lambda
resource "null_resource" "build_lambda" {
  triggers = {
    package_json = filemd5("${path.module}/../../../packages/database/package.json")
    migrate_js = filemd5("${path.module}/../../../packages/database/src/migrate.js")
    migrations = sha256(join("", [
      for f in fileset("${path.module}/../../../packages/database/migrations", "*.sql") :
      filemd5("${path.module}/../../../packages/database/migrations/${f}")
    ]))
  }

  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ${path.module}/lambda
      rm -rf ${path.module}/lambda/package
      mkdir -p ${path.module}/lambda/package
      cp -r ${path.module}/../../../packages/database/* ${path.module}/lambda/package/
      cd ${path.module}/lambda/package && npm install --production && cd .. && zip -r function.zip package/
    EOT
  }
}

# Calculate Lambda hash
data "external" "lambda_hash" {
  program = ["bash", "-c", <<-EOT
    if [ -f "${path.module}/lambda/function.zip" ]; then
      echo "{\"hash\": \"$(openssl dgst -sha256 -binary ${path.module}/lambda/function.zip | openssl base64)\"}"
    else
      echo "{\"hash\": \"\"}"
    fi
  EOT
  ]
  depends_on = [null_resource.build_lambda]
}

# Lambda function for database migrations
resource "aws_lambda_function" "db_migrate" {
  filename         = "${path.module}/lambda/function.zip"
  source_code_hash = data.external.lambda_hash.result.hash
  function_name    = "${var.environment}-db-migrate"
  role            = aws_iam_role.lambda_role.arn
  handler         = "src/migrate.migrate"
  runtime         = "nodejs18.x"
  timeout         = 300  # 5 minutes

  environment {
    variables = {
      DB_HOST               = aws_db_instance.main.endpoint
      DB_PASSWORD_SECRET_ARN = var.db_password_secret_arn
      DB_NAME               = "messages"
      DB_USER               = "postgres"
      ENVIRONMENT           = var.environment
      MIGRATION_STATUS_PARAM = "/${var.environment}/migration-status"
    }
  }

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_vpc,
    aws_iam_role_policy_attachment.lambda_basic,
    null_resource.build_lambda
  ]
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
  name = "${var.environment}-db-migrate-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Allow Lambda to access VPC
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Basic Lambda execution permissions
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Allow Lambda to access Secrets Manager and SSM
resource "aws_iam_role_policy" "lambda_secrets" {
  name = "${var.environment}-lambda-secrets"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "ssm:PutParameter",
          "ssm:GetParameter"
        ]
        Resource = [
          var.db_password_secret_arn,
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${var.environment}/migration-status"
        ]
      }
    ]
  })
}

# Get current AWS region and account ID
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