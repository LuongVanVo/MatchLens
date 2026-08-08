data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

locals {
  name_prefix = "matchlens-${var.environment}"

  video_jobs_queue_name              = "${local.name_prefix}-video-processing-jobs"
  video_jobs_dlq_name                = "${local.name_prefix}-video-processing-dlq"
  status_callbacks_queue_name        = "${local.name_prefix}-match-status-callbacks"
  status_callbacks_dlq_name          = "${local.name_prefix}-match-status-callbacks-dlq"
  dispatcher_lambda_name             = "${local.name_prefix}-job-dispatcher-fn"
  status_updater_lambda_name         = "${local.name_prefix}-status-updater-fn"
  mediaconvert_trigger_lambda_name   = "${local.name_prefix}-mediaconvert-trigger-fn"
  status_updater_security_group_name = "${local.name_prefix}-status-updater-sg"

  common_component_tags = {
    Component = "messaging"
  }

  dispatcher_service_tags = {
    Service = "job-dispatcher"
  }

  status_updater_service_tags = {
    Service            = "status-updater"
    DataClassification = "confidential"
  }

  mediaconvert_trigger_service_tags = {
    Service = "mediaconvert-trigger"
  }

  lambda_source_hashes = {
    dispatcher           = filebase64sha256(var.dispatcher_lambda_zip_path)
    status_updater       = filebase64sha256(var.status_updater_lambda_zip_path)
    mediaconvert_trigger = filebase64sha256(var.mediaconvert_trigger_lambda_zip_path)
  }
}