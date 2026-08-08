resource "aws_sqs_queue" "status_callbacks_dlq" {
  name                      = local.status_callbacks_dlq_name
  message_retention_seconds = 1209600

  tags = merge(local.common_component_tags, {
    Name    = local.status_callbacks_dlq_name
    Service = "status-callbacks"
  })
}

resource "aws_sqs_queue" "status_callbacks" {
  name                       = local.status_callbacks_queue_name
  message_retention_seconds  = 345600
  visibility_timeout_seconds = 360 # Phải lớn hơn hoặc bằng Lambda timeout (60s). AWS khuyến nghị set gấp 6 lần.

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.status_callbacks_dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = merge(local.common_component_tags, {
    Name    = local.status_callbacks_queue_name
    Service = "status-callbacks"
  })
}
