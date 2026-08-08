resource "aws_lambda_function" "job_dispatcher" {
  function_name = local.dispatcher_lambda_name
  role          = var.dispatcher_role_arn

  filename         = var.dispatcher_lambda_zip_path
  source_code_hash = local.lambda_source_hashes.dispatcher

  runtime = var.lambda_runtime
  handler = "main.handler"
  timeout = var.lambda_timeout_seconds

  environment {
    variables = {
      VIDEO_PROCESSING_QUEUE_URL = aws_sqs_queue.video_processing_jobs.id
      STATUS_CALLBACKS_QUEUE_URL = aws_sqs_queue.status_callbacks.id
      RAW_VIDEOS_BUCKET_NAME     = var.raw_videos_bucket_name
      EXPECTED_OBJECT_SUFFIX     = "original.mp4"
    }
  }

  tags = merge(
    local.common_component_tags,
    local.dispatcher_service_tags,
    {
      Name = local.dispatcher_lambda_name
    }
  )
}

resource "aws_lambda_permission" "allow_raw_videos_bucket_invoke_dispatcher" {
  statement_id  = "AllowExecutionFromRawVideosBucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.job_dispatcher.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = var.raw_videos_bucket_arn
}