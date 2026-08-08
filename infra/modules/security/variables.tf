variable "environment" {
  description = "Environment name: dev, staging, prod"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod"
  }
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "matchlens"
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-southeast-1"
}

variable "github_org" {
  description = "Github org or username"
  type        = string
}

variable "github_repo" {
  description = "Github repository name"
  type        = string
  default     = "MatchLens"
}

variable "raw_videos_bucket_arn" {
  description = "ARN of raw-video bucket"
  type        = string
}

variable "processed_highlights_bucket_arn" {
  description = "ARN of processed-highlights bucket"
  type        = string
}

variable "raw_tracking_data_bucket_arn" {
  description = "ARN of raw-tracking-data bucket"
  type        = string
}

variable "curated_data_bucket_arn" {
  description = "ARN of curated-data bucket"
  type        = string
}

variable "athena_results_bucket_arn" {
  description = "ARN of athena-results bucket"
  type        = string
}

variable "dynamodb_table_arn" {
  description = "ARN of DynamoDB match-events table"
  type        = string
}

variable "db_secret_arn" {
  description = "ARN of RDS credentials secret from database module"
  type        = string
}

variable "alert_sns_topic_arn" {
  description = "SNS topic ARN for security findings notifications"
  type        = string
  default     = null
}

variable "owner" {
  description = "Owner tag"
  type        = string
  default     = "voluongdev"
}
