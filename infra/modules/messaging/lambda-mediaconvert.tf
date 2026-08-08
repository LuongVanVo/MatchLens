resource "aws_lambda_function" "mediaconvert_trigger" {
  function_name = local.mediaconvert_trigger_lambda_name
  role          = var.mediaconvert_trigger_role_arn

  filename         = var.mediaconvert_trigger_lambda_zip_path
  source_code_hash = local.lambda_source_hashes.mediaconvert_trigger

  runtime = var.lambda_runtime
  handler = "main.handler"
  timeout = var.lambda_timeout_seconds

  environment {
    variables = {
      MEDIACONVERT_ROLE_ARN       = var.mediaconvert_role_arn
      PROCESSED_HIGHLIGHTS_BUCKET = var.processed_highlights_bucket_name
      MEDIACONVERT_INPUT_PREFIX   = "raw-clips/"
      MEDIACONVERT_OUTPUT_PREFIX  = "clips/"
    }
  }

  tags = merge(
    local.common_component_tags,
    local.mediaconvert_trigger_service_tags,
    {
      Name = local.mediaconvert_trigger_lambda_name
    }
  )
}

resource "aws_lambda_permission" "allow_processed_highlights_bucket_invoke_mediaconvert" {
  statement_id  = "AllowExecutionFromProcessedHighlightsBucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.mediaconvert_trigger.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = var.processed_highlights_bucket_arn
}