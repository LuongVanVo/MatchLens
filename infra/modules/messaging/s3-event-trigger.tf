resource "aws_s3_bucket_notification" "raw_videos" {
  bucket = var.raw_videos_bucket_name

  lambda_function {
    lambda_function_arn = aws_lambda_function.job_dispatcher.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [
    aws_lambda_permission.allow_raw_videos_bucket_invoke_dispatcher
  ]
}

resource "aws_s3_bucket_notification" "processed_highlights" {
  bucket = var.processed_highlights_bucket_name

  lambda_function {
    lambda_function_arn = aws_lambda_function.mediaconvert_trigger.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "raw-clips/"
  }

  depends_on = [
    aws_lambda_permission.allow_processed_highlights_bucket_invoke_mediaconvert
  ]
}