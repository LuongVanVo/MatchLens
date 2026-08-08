resource "aws_security_group" "status_updater_lambda" {
  name        = local.status_updater_security_group_name
  description = "Security group for status updater Lambda"
  vpc_id      = var.vpc_id

  egress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.rds_security_group_id]
  }

  tags = merge(
    local.common_component_tags,
    local.status_updater_service_tags,
    {
      Name = local.status_updater_security_group_name
    }
  )
}

resource "aws_lambda_function" "status_updater" {
  function_name = local.status_updater_lambda_name
  role          = var.status_updater_role_arn

  filename         = var.status_updater_lambda_zip_path
  source_code_hash = local.lambda_source_hashes.status_updater

  runtime = var.lambda_runtime
  handler = "main.handler"
  timeout = var.status_updater_timeout_seconds

  vpc_config {
    subnet_ids         = var.private_app_subnet_ids
    security_group_ids = [aws_security_group.status_updater_lambda.id]
  }

  environment {
    variables = {
      STATUS_CALLBACKS_QUEUE_URL = aws_sqs_queue.status_callbacks.id
      DB_SECRET_ARN              = var.db_secret_arn
    }
  }

  tags = merge(
    local.common_component_tags,
    local.status_updater_service_tags,
    {
      Name = local.status_updater_lambda_name
    }
  )
}

resource "aws_lambda_event_source_mapping" "status_callbacks_consumer" {
  event_source_arn = aws_sqs_queue.status_callbacks.arn
  function_name    = aws_lambda_function.status_updater.function_name
  batch_size       = 10
  enabled          = true
}