resource "aws_ecs_cluster" "this" {
  name = local.cluster_name

  setting {
    name  = "containerInsights" # Bật CloudWatch container insights giúp AWS tự động thu thập logs, metrics và trace của container
    value = "enabled"
  }

  tags = merge(local.common_tags, {
    Name = local.cluster_name
  })
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${local.backend_service_name}"
  retention_in_days = var.backend_log_retention_days

  tags = merge(local.common_tags, {
    Name = "/ecs/${local.backend_service_name}"
  })
}

resource "aws_ecs_task_definition" "backend" {
  family                   = local.backend_task_family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.backend_cpu)
  memory                   = tostring(var.backend_memory)
  execution_role_arn       = var.backend_task_execution_role_arn
  task_role_arn            = var.backend_task_role_arn

  container_definitions = jsonencode([
    {
      name      = local.backend_container_name
      image     = var.backend_image_uri
      essential = true

      portMappings = [
        {
          containerPort = var.backend_container_port
          hostPort      = var.backend_container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "NODE_ENV"
          value = var.environment
        },
        {
          name  = "PORT"
          value = tostring(var.backend_container_port)
        },
        {
          name  = "DATABASE_URL_MASTER"
          value = var.database_url_master
        },
        {
          name  = "DATABASE_URL_REPLICA"
          value = var.database_url_replica
        },
        {
          name  = "JWT_ACCESS_PUBLIC_KEY"
          value = var.jwt_access_public_key
        },
        {
          name  = "JWT_ACCESS_PRIVATE_KEY"
          value = var.jwt_access_private_key
        },
        {
          name  = "JWT_REFRESH_PRIVATE_KEY"
          value = var.jwt_refresh_private_key
        },
        {
          name  = "RAW_VIDEOS_BUCKET_NAME"
          value = var.raw_videos_bucket_name
        },
        {
          name  = "PROCESSED_HIGHLIGHTS_BUCKET_NAME"
          value = var.processed_highlights_bucket_name
        },
        {
          name  = "RAW_TRACKING_BUCKET_NAME"
          value = var.raw_tracking_bucket_name
        },
        {
          name  = "MATCH_EVENTS_TABLE_NAME"
          value = var.dynamodb_table_name
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.backend.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.backend_container_port}${var.backend_health_check_path} || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
    }
  ])

  tags = merge(local.common_tags, {
    Name = local.backend_task_family
  })
}

resource "aws_ecs_service" "backend" {
  name            = local.backend_service_name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = var.backend_desired_count
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
  enable_execute_command             = false

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = local.backend_container_name
    container_port   = var.backend_container_port
  }

  depends_on = [
    aws_lb_listener.http
  ]

  tags = merge(local.common_tags, {
    Name = local.backend_service_name
  })
}