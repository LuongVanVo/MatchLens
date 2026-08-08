resource "aws_sqs_queue" "video_processing_dlq" {
  name = local.video_jobs_dlq_name

  message_retention_seconds = 1209600 # 14 days

  tags = merge(local.common_component_tags, {
    Name    = local.video_jobs_dlq_name
    Service = "video-processing"
  })
}

resource "aws_sqs_queue" "video_processing_jobs" {
  name                      = local.video_jobs_queue_name
  message_retention_seconds = 345600 # 4 days

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.video_processing_dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = merge(local.common_component_tags, {
    Name    = local.video_jobs_queue_name
    Service = "video-processing"
  })
}