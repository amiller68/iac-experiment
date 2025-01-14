# ECR Repositories
resource "aws_ecr_repository" "api_service" {
  name = "${var.environment}-api-service"
  
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Environment = var.environment
  }
}

resource "aws_ecr_repository" "web_service" {
  name = "${var.environment}-web-service"
  
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Environment = var.environment
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.environment}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Environment = var.environment
  }
}

# ALB Security Group
resource "aws_security_group" "alb" {
  name        = "${var.environment}-alb-sg"
  description = "Security group for ALB"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
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

# Service Security Groups
resource "aws_security_group" "api_service" {
  name        = "${var.environment}-api-service-sg"
  description = "Security group for API service"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
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

resource "aws_security_group" "web_service" {
  name        = "${var.environment}-web-service-sg"
  description = "Security group for web service"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 3001
    to_port         = 3001
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
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

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets           = var.public_subnet_ids

  tags = {
    Environment = var.environment
  }
}

# ALB Target Groups
resource "aws_lb_target_group" "api_service" {
  name        = "${var.environment}-api-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 10
    interval            = 30
    timeout             = 5
    matcher            = "200"
  }

  tags = {
    Environment = var.environment
  }
}

resource "aws_lb_target_group" "web_service" {
  name        = "${var.environment}-web-tg"
  port        = 3001
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 10
    interval            = 30
    timeout             = 5
    matcher            = "200"
  }

  tags = {
    Environment = var.environment
  }
}

# ALB Listeners
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_service.arn
  }
}

resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_service.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}

# ECS Task Execution Role
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.environment}-ecs-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Definitions
resource "aws_ecs_task_definition" "api_service" {
  family                   = "${var.environment}-api-service"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.api_service_cpu
  memory                   = var.api_service_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name  = "api-service"
      image = "${aws_ecr_repository.api_service.repository_url}:latest"
      portMappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "DB_HOST"
          value = var.db_host
        },
        {
          name  = "DB_PORT"
          value = "5432"
        },
        {
          name  = "DB_NAME"
          value = "messages"
        },
        {
          name  = "BASE_PATH"
          value = "/api"
        }
      ]
      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = aws_secretsmanager_secret_version.db_password.arn
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/${var.environment}/api-service"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = {
    Environment = var.environment
  }
}

resource "aws_ecs_task_definition" "web_service" {
  family                   = "${var.environment}-web-service"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.web_service_cpu
  memory                   = var.web_service_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name  = "web-service"
      image = "${aws_ecr_repository.web_service.repository_url}:latest"
      portMappings = [
        {
          containerPort = 3001
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "API_URL"
          value = "http://${aws_lb.main.dns_name}/api"
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "static-assets"
          containerPath = "/app/public"
          readOnly      = false
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/${var.environment}/web-service"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  volume {
    name = "static-assets"
    efs_volume_configuration {
      file_system_id = var.efs_id
      root_directory = "/"
    }
  }

  tags = {
    Environment = var.environment
  }
}

# Create or read SSM parameter for migration status
resource "aws_ssm_parameter" "migration_status" {
  name  = var.migration_status_param_name
  type  = "String"
  value = "pending"  # Default value

  lifecycle {
    ignore_changes = [value]  # Ignore changes since Lambda will update it
  }
}

# ECS Services
resource "aws_ecs_service" "api_service" {
  name            = "api-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api_service.arn
  desired_count   = var.api_service_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.api_service.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api_service.arn
    container_name   = "api-service"
    container_port   = 3000
  }

  tags = {
    Environment = var.environment
  }

  depends_on = [aws_ssm_parameter.migration_status]

  lifecycle {
    precondition {
      condition     = aws_ssm_parameter.migration_status.value == "complete"
      error_message = "Database migrations must complete before services can start"
    }
  }
}

resource "aws_ecs_service" "web_service" {
  name            = "web-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.web_service.arn
  desired_count   = var.web_service_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.web_service.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.web_service.arn
    container_name   = "web-service"
    container_port   = 3001
  }

  tags = {
    Environment = var.environment
  }

  depends_on = [aws_ssm_parameter.migration_status]

  lifecycle {
    precondition {
      condition     = aws_ssm_parameter.migration_status.value == "complete"
      error_message = "Database migrations must complete before services can start"
    }
  }
}

# Create a secret in AWS Secrets Manager
resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${var.environment}-db-password"
  recovery_window_in_days = 0  # Set to 0 to force deletion without waiting

  lifecycle {
    prevent_destroy = false
  }
}

# Add a time delay after secret deletion
resource "time_sleep" "wait_for_secret_deletion" {
  depends_on = [aws_secretsmanager_secret.db_password]

  create_duration = "10s"
}

# Update the secret version to depend on the time delay
resource "aws_secretsmanager_secret_version" "db_password" {
  depends_on = [time_sleep.wait_for_secret_deletion]
  
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = var.database_password
}

# Add permissions to ECS task execution role
resource "aws_iam_role_policy_attachment" "task_execution_secrets" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = aws_iam_policy.secrets_access.arn
}

resource "aws_iam_policy" "secrets_access" {
  name = "${var.environment}-ecs-secrets-access"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [aws_secretsmanager_secret.db_password.arn]
      }
    ]
  })
} 