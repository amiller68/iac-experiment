# CloudWatch Log Groups
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

# Security Group for Monitoring
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

# ECS Task Definition for Prometheus
resource "aws_ecs_task_definition" "prometheus" {
  family                   = "${var.environment}-prometheus"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.prometheus_cpu
  memory                   = var.prometheus_memory
  execution_role_arn       = var.ecs_task_execution_role_arn

  container_definitions = jsonencode([
    {
      name  = "prometheus"
      image = "prom/prometheus:v2.42.0"
      portMappings = [
        {
          containerPort = 9090
          protocol      = "tcp"
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "prometheus-config"
          containerPath = "/etc/prometheus"
          readOnly      = true
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/${var.environment}/prometheus"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  volume {
    name = "prometheus-config"
    efs_volume_configuration {
      file_system_id = var.efs_id
      root_directory = "/prometheus"
    }
  }

  tags = {
    Environment = var.environment
  }
}

# ECS Task Definition for Grafana
resource "aws_ecs_task_definition" "grafana" {
  family                   = "${var.environment}-grafana"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.grafana_cpu
  memory                   = var.grafana_memory
  execution_role_arn       = var.ecs_task_execution_role_arn

  container_definitions = jsonencode([
    {
      name  = "grafana"
      image = "grafana/grafana:9.5.2"
      portMappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "GF_SECURITY_ADMIN_PASSWORD"
          value = var.grafana_admin_password
        },
        {
          name  = "GF_INSTALL_PLUGINS"
          value = "grafana-piechart-panel,grafana-worldmap-panel"
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "grafana-storage"
          containerPath = "/var/lib/grafana"
          readOnly      = false
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/${var.environment}/grafana"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  volume {
    name = "grafana-storage"
    efs_volume_configuration {
      file_system_id = var.efs_id
      root_directory = "/grafana"
    }
  }

  tags = {
    Environment = var.environment
  }
}

# ECS Services
resource "aws_ecs_service" "prometheus" {
  name            = "prometheus"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.prometheus.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.monitoring.id]
    assign_public_ip = false
  }

  tags = {
    Environment = var.environment
  }
}

resource "aws_ecs_service" "grafana" {
  name            = "grafana"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.grafana.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.monitoring.id]
    assign_public_ip = false
  }

  tags = {
    Environment = var.environment
  }
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "api_service_errors" {
  alarm_name          = "${var.environment}-api-service-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "http_request_errors_total"
  namespace           = "ECS/ContainerInsights"
  period             = "300"
  statistic          = "Sum"
  threshold          = "10"
  alarm_description  = "This metric monitors api service error rate"
  alarm_actions      = [var.sns_topic_arn]

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = "api-service"
  }
}

resource "aws_cloudwatch_metric_alarm" "web_service_errors" {
  alarm_name          = "${var.environment}-web-service-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "http_request_errors_total"
  namespace           = "ECS/ContainerInsights"
  period             = "300"
  statistic          = "Sum"
  threshold          = "10"
  alarm_description  = "This metric monitors web service error rate"
  alarm_actions      = [var.sns_topic_arn]

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = "web-service"
  }
}

# EC2 Instance for Monitoring
resource "aws_instance" "monitoring" {
  ami           = var.monitoring_ami # Amazon Linux 2 AMI
  instance_type = "t3.small"
  subnet_id     = var.private_subnet_ids[0]
  
  vpc_security_group_ids = [aws_security_group.monitoring.id]
  iam_instance_profile   = aws_iam_instance_profile.monitoring.name

  user_data = templatefile("${path.module}/user_data.sh", {
    grafana_admin_password = var.grafana_admin_password
    prometheus_config = local.prometheus_config
    grafana_datasource_config = local.grafana_datasource_config
    grafana_dashboard_config = local.grafana_dashboard_config
    grafana_dashboard = local.grafana_dashboard
  })

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = {
    Name        = "${var.environment}-monitoring"
    Environment = var.environment
  }
}

# Dedicated EBS volume for monitoring data
resource "aws_ebs_volume" "monitoring_data" {
  availability_zone = aws_instance.monitoring.availability_zone
  size             = 100
  type             = "gp3"

  tags = {
    Name = "${var.environment}-monitoring-data"
  }
}

resource "aws_volume_attachment" "monitoring_data" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.monitoring_data.id
  instance_id = aws_instance.monitoring.id
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

  grafana_datasource_config = templatefile("${path.module}/grafana/datasources/prometheus.yaml", {})
  grafana_dashboard_config = file("${path.module}/grafana/dashboards/dashboards.yaml")
  grafana_dashboard = file("${path.module}/grafana/dashboards/request-metrics.json")
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