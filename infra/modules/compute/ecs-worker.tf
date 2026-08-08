resource "aws_cloudwatch_log_group" "worker" {
  count = local.create_worker ? 1 : 0

  name              = "ecs/${local.worker_service_name}"
  retention_in_days = var.worker_log_retention_days

  tags = merge(local.common_tags, {
    Name = "ecs/${local.worker_service_name}"
  })
}

resource "aws_ecs_task_definition" "worker" {
  count = local.create_worker ? 1 : 0

  family                   = local.worker_task_family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.worker_cpu)
  memory                   = tostring(var.worker_memory)
  execution_role_arn       = var.worker_task_execution_role_arn
  task_role_arn            = var.worker_task_role_arn

  container_definitions = jsonencode([
    {
      name      = local.worker_container_name
      image     = var.worker_image_uri
      essential = true

      environment = [
        {
          name  = "ENVIRONMENT"
          value = var.environment
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "VIDEO_PROCESSING_QUEUE_URL"
          value = var.video_processing_queue_url
        },
        {
          name  = "STATUS_CALLBACKS_QUEUE_URL"
          value = var.status_callbacks_queue_url
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
          name  = "POLLING_INTERVAL_SECONDS"
          value = tostring(var.worker_polling_interval_seconds)
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.worker[0].name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = merge(local.common_tags, {
    Name = local.worker_task_family
  })
}

resource "aws_ecs_service" "worker" {
  count = local.create_worker ? 1 : 0

  name            = local.worker_service_name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.worker[0].arn
  desired_count   = var.worker_desired_count
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  enable_execute_command             = false

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  tags = merge(local.common_tags, {
    Name = local.worker_service_name
  })
}