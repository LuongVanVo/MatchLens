data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Component = "security"
    ManagedBy = "Terraform"
    Owner     = var.owner
  }

  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.name

  video_jobs_queue_name       = "${local.name_prefix}-video-processing-jobs"
  status_callbacks_queue_name = "${local.name_prefix}-match-status-callbacks"
  ecs_cluster_name            = "${local.name_prefix}-cluster"

  video_jobs_queue_arn       = "arn:${local.partition}:sqs:${local.region}:${local.account_id}:${local.video_jobs_queue_name}"
  status_callbacks_queue_arn = "arn:${local.partition}:sqs:${local.region}:${local.account_id}:${local.status_callbacks_queue_name}"
  ecs_cluster_arn            = "arn:${local.partition}:ecs:${local.region}:${local.account_id}:cluster/${local.ecs_cluster_name}"

  backend_task_role_name           = "${local.name_prefix}-backend-task-role"
  backend_task_execution_role_name = "${local.name_prefix}-backend-task-execution-role"
  worker_task_role_name            = "${local.name_prefix}-worker-task-role"
  worker_task_execution_role_name  = "${local.name_prefix}-worker-task-execution-role"
  dispatcher_lambda_role_name      = "${local.name_prefix}-dispatcher-lambda-role"
  status_updater_lambda_role_name  = "${local.name_prefix}-status-updater-lambda-role"
  mediaconvert_trigger_role_name   = "${local.name_prefix}-mediaconvert-trigger-lambda-role"
  mediaconvert_service_role_name   = "${local.name_prefix}-mediaconvert-service-role"
  glue_job_role_name               = "${local.name_prefix}-glue-job-role"
  github_actions_role_name         = "${local.name_prefix}-github-actions-role"

  jwt_key_secret_name            = "${local.name_prefix}-jwt-keypair-secret"
  cloudfront_signing_secret_name = "${local.name_prefix}-cloudfront-signing-key-secret"

  github_oidc_subjects = {
    dev     = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/develop"
    staging = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"
    prod    = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"
  }

  github_oidc_subject = local.github_oidc_subjects[var.environment]
}
