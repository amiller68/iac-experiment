# Single EC2 instance for both Prometheus and Grafana
resource "aws_instance" "monitoring" {
  ami           = var.monitoring_ami
  instance_type = "t3.small"
  subnet_id     = var.private_subnet_ids[0]
  
  vpc_security_group_ids = [aws_security_group.monitoring.id]
  iam_instance_profile   = aws_iam_instance_profile.monitoring.name

  user_data = templatefile("${path.module}/user_data.sh", {
    grafana_admin_secret_arn = var.grafana_admin_secret_arn
    prometheus_config = local.prometheus_config
    aws_region = var.aws_region
  })

  root_block_device {
    volume_size = var.monitoring_volume_size  # This is already set to 100GB
    volume_type = "gp3"
    encrypted   = true
    
    tags = {
      Name        = "${var.environment}-monitoring"
      Environment = var.environment
    }
  }
}

# Security group for monitoring
resource "aws_security_group" "monitoring" {
  name        = "${var.environment}-monitoring-sg"
  description = "Security group for monitoring instance"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 9090
    to_port         = 9090
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  # Allow ECS services to access Prometheus
  ingress {
    from_port       = 9090
    to_port         = 9090
    protocol        = "tcp"
    security_groups = [var.api_service_security_group_id, var.web_service_security_group_id]
    description     = "Allow ECS services to scrape metrics"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# IAM Role for EC2 Monitoring Instance
resource "aws_iam_role" "monitoring" {
  name = "${var.environment}-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "monitoring" {
  name = "${var.environment}-monitoring-profile"
  role = aws_iam_role.monitoring.name
}

resource "aws_iam_role_policy_attachment" "monitoring_policy" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# ALB Target Groups for Monitoring
resource "aws_lb_target_group" "prometheus" {
  name        = "${var.environment}-prometheus"
  port        = 9090
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    path                = "/-/healthy"
    healthy_threshold   = 2
    unhealthy_threshold = 10
  }
}

resource "aws_lb_target_group" "grafana" {
  name        = "${var.environment}-grafana"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    path                = "/api/health"
    healthy_threshold   = 2
    unhealthy_threshold = 10
  }
}

# Target Group Attachments
resource "aws_lb_target_group_attachment" "prometheus" {
  target_group_arn = aws_lb_target_group.prometheus.arn
  target_id        = aws_instance.monitoring.id
  port             = 9090
}

resource "aws_lb_target_group_attachment" "grafana" {
  target_group_arn = aws_lb_target_group.grafana.arn
  target_id        = aws_instance.monitoring.id
  port             = 3000
}

locals {
  prometheus_config = templatefile("${path.module}/prometheus.yml", {
    aws_region = var.aws_region
    monitoring_role_arn = aws_iam_role.monitoring.arn
  })
}

resource "aws_iam_role_policy" "prometheus_discovery" {
  name = "${var.environment}-prometheus-discovery"
  role = aws_iam_role.monitoring.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:ListClusters",
          "ecs:ListTasks",
          "ecs:DescribeTask",
          "ec2:DescribeInstances",
          "ecs:DescribeContainerInstances",
          "ecs:DescribeTasks",
          "ecs:DescribeTaskDefinition"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "grafana_secrets_access" {
  name = "${var.environment}-grafana-secrets-access"
  role = split("/", var.ecs_task_execution_role_arn)[1]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [var.grafana_admin_secret_arn]
      }
    ]
  })
}

# Add log retention policy
resource "aws_cloudwatch_log_group" "monitoring" {
  name              = "/aws/monitoring/${var.environment}"
  retention_in_days = 30

  tags = {
    Environment = var.environment
  }
}

# Add CloudWatch Log Groups for services
resource "aws_cloudwatch_log_group" "api_service" {
  name              = "/ecs/${var.environment}/api-service"
  retention_in_days = 30

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "web_service" {
  name              = "/ecs/${var.environment}/web-service"
  retention_in_days = 30

  tags = {
    Environment = var.environment
  }
}

# Add CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "api_service_errors" {
  alarm_name          = "${var.environment}-api-service-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name        = "HTTPCode_Target_5XX_Count"
  namespace          = "AWS/ApplicationELB"
  period             = "300"
  statistic          = "Sum"
  threshold          = "10"
  alarm_description  = "This metric monitors API service 5XX errors"
  alarm_actions      = [var.sns_topic_arn]

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.api_target_group_arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "web_service_errors" {
  alarm_name          = "${var.environment}-web-service-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name        = "HTTPCode_Target_5XX_Count"
  namespace          = "AWS/ApplicationELB"
  period             = "300"
  statistic          = "Sum"
  threshold          = "10"
  alarm_description  = "This metric monitors web service 5XX errors"
  alarm_actions      = [var.sns_topic_arn]

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.web_target_group_arn_suffix
  }
} 