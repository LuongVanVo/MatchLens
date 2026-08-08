variable "environment" {
  description = "Environment name: dev, staging, prod"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-1"
}

variable "raw_videos_bucket_arn" {
  description = "ARN of the raw videos bucket"
  type        = string
}

variable "raw_videos_bucket_name" {
  description = "Name of the raw videos bucket"
  type        = string
}

variable "processed_highlights_bucket_arn" {
  description = "ARN of the processed highlights bucket"
  type        = string
}

variable "processed_highlights_bucket_name" {
  description = "Name of the processed highlights bucket"
  type        = string
}

variable "private_app_subnet_ids" {
  description = "Private app subnet IDs for VPC-enabled Lambda"
  type        = list(string)
}

variable "dispatcher_role_arn" {
  description = "IAM role ARN for job dispatcher Lambda"
  type        = string
}

variable "status_updater_role_arn" {
  description = "IAM role ARN for status updater Lambda"
  type        = string
}

variable "mediaconvert_trigger_role_arn" {
  description = "IAM role ARN for MediaConvert trigger Lambda"
  type        = string
}

variable "mediaconvert_role_arn" {
  description = "IAM service role ARN passed to MediaConvert jobs"
  type        = string
}

variable "db_secret_arn" {
  description = "Secrets Manager ARN for database credentials"
  type        = string
}

variable "rds_security_group_id" {
  description = "Security group ID of the RDS instance"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the status updater Lambda runs"
  type        = string
}

variable "max_receive_count" {
  description = "Max receive count before moving messages to the DLQ"
  type        = number
  default     = 3
}

variable "visibility_timeout" {
  description = "Visibility timeout for both SQS queues in seconds"
  type        = number
  default     = 900
}

variable "dispatcher_lambda_zip_path" {
  description = "Path to the packaged job dispatcher Lambda zip"
  type        = string
  default     = "../../../lambdas/job_dispatcher/function.zip"
}

variable "status_updater_lambda_zip_path" {
  description = "Path to the packaged status updater Lambda zip"
  type        = string
  default     = "../../../lambdas/status_updater/function.zip"
}

variable "mediaconvert_trigger_lambda_zip_path" {
  description = "Path to the packaged MediaConvert trigger Lambda zip"
  type        = string
  default     = "../../../lambdas/mediaconvert_trigger/function.zip"
}

variable "lambda_runtime" {
  description = "Python runtime for all messaging Lambdas"
  type        = string
  default     = "python3.12"
}

variable "lambda_timeout_seconds" {
  description = "Default timeout for dispatcher and MediaConvert trigger Lambdas"
  type        = number
  default     = 30
}

variable "status_updater_timeout_seconds" {
  description = "Timeout for the status updater Lambda"
  type        = number
  default     = 60
}