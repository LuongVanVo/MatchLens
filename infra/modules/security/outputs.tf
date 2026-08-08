output "backend_task_role_arn" {
  value = aws_iam_role.backend_task.arn
}

output "worker_task_role_arn" {
  value = aws_iam_role.worker_task.arn
}

output "dispatcher_lambda_role_arn" {
  value = aws_iam_role.dispatcher_lambda.arn
}

output "status_updater_lambda_role_arn" {
  value = aws_iam_role.status_updater_lambda.arn
}

output "mediaconvert_trigger_lambda_role_arn" {
  value = aws_iam_role.mediaconvert_trigger_lambda.arn
}

output "mediaconvert_service_role_arn" {
  value = aws_iam_role.mediaconvert_service.arn
}

output "glue_job_role_arn" {
  value = aws_iam_role.glue_job.arn
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}

output "github_oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github_actions.arn
}

output "jwt_keypair_secret_arn" {
  value = aws_secretsmanager_secret.jwt_keypair.arn
}

output "cloudfront_signing_key_secret_arn" {
  value = aws_secretsmanager_secret.cloudfront_signing_key.arn
}

output "backend_task_execution_role_arn" {
  description = "ARN of the ECS backend task execution role"
  value       = aws_iam_role.backend_task_execution.arn
}

output "worker_task_execution_role_arn" {
  description = "ARN of the ECS worker task execution role"
  value       = aws_iam_role.worker_task_execution.arn
}