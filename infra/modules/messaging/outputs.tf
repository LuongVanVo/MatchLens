output "video_processing_queue_name" {
  value = aws_sqs_queue.video_processing_jobs.name
}

output "video_processing_queue_url" {
  value = aws_sqs_queue.video_processing_jobs.id
}

output "video_processing_queue_arn" {
  value = aws_sqs_queue.video_processing_jobs.arn
}

output "video_processing_dlq_name" {
  value = aws_sqs_queue.video_processing_dlq.name
}

output "video_processing_dlq_arn" {
  value = aws_sqs_queue.video_processing_dlq.arn
}

output "status_callbacks_queue_name" {
  value = aws_sqs_queue.status_callbacks.name
}

output "status_callbacks_queue_url" {
  value = aws_sqs_queue.status_callbacks.id
}

output "status_callbacks_queue_arn" {
  value = aws_sqs_queue.status_callbacks.arn
}

output "status_callbacks_dlq_name" {
  value = aws_sqs_queue.status_callbacks_dlq.name
}

output "status_callbacks_dlq_arn" {
  value = aws_sqs_queue.status_callbacks_dlq.arn
}

output "job_dispatcher_lambda_arn" {
  value = aws_lambda_function.job_dispatcher.arn
}

output "status_updater_lambda_arn" {
  value = aws_lambda_function.status_updater.arn
}

output "mediaconvert_trigger_lambda_arn" {
  value = aws_lambda_function.mediaconvert_trigger.arn
}

output "status_updater_lambda_security_group_id" {
  value = aws_security_group.status_updater_lambda.id
}