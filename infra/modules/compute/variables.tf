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
  description = "AWS region"
  type        = string
  default     = "ap-southeast-1"
}

variable "owner" {
  description = "Owner tag"
  type        = string
  default     = "voluongdev"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for ALB"
  type        = list(string)
}

variable "private_app_subnet_ids" {
  description = "Private app subnet IDs for ECS services"
  type        = list(string)
}

variable "backend_image_uri" {
  description = "ECR image URI for backend container"
  type        = string
}

variable "worker_image_uri" {
  description = "ECR image URI for worker container"
  type        = string
  default     = null
}

variable "backend_task_role_arn" {
  description = "IAM task role ARN for backend ECS task"
  type        = string
}

variable "backend_task_execution_role_arn" {
  description = "IAM execution role ARN for backend ECS task"
  type        = string
}

variable "worker_task_role_arn" {
  description = "IAM task role ARN for worker ECS task"
  type        = string
  default     = null
}

variable "worker_task_execution_role_arn" {
  description = "IAM execution role ARN for worker ECS task"
  type        = string
  default     = null
}

variable "backend_container_port" {
  description = "Backend container port"
  type        = number
  default     = 3000
}

variable "backend_cpu" {
  description = "Backend task CPU units"
  type        = number
  default     = 512
}

variable "backend_memory" {
  description = "Backend task memory in MiB"
  type        = number
  default     = 1024
}

variable "backend_desired_count" {
  description = "Desired number of backend tasks"
  type        = number
  default     = 1
}

variable "backend_min_capacity" {
  description = "Minimum backend task count"
  type        = number
  default     = 1
}

variable "backend_max_capacity" {
  description = "Maximum backend task count"
  type        = number
  default     = 2
}

variable "backend_health_check_path" {
  description = "Health check path for backend target group"
  type        = string
  default     = "/health"
}

variable "backend_health_check_matcher" {
  description = "Expected HTTP code for backend health check"
  type        = string
  default     = "200"
}

variable "backend_log_retention_days" {
  description = "CloudWatch log retention for backend"
  type        = number
  default     = 14
}

variable "database_url_master" {
  description = "Master database connection string"
  type        = string
  sensitive   = true
}

variable "database_url_replica" {
  description = "Read replica database connection string"
  type        = string
  sensitive   = true
}

variable "jwt_access_public_key" {
  description = "JWT access public key PEM"
  type        = string
  sensitive   = true
}

variable "jwt_access_private_key" {
  description = "JWT access private key PEM"
  type        = string
  sensitive   = true
}

variable "jwt_refresh_private_key" {
  description = "JWT refresh private key PEM"
  type        = string
  sensitive   = true
}

variable "raw_videos_bucket_name" {
  description = "Raw videos bucket name"
  type        = string
}

variable "processed_highlights_bucket_name" {
  description = "Processed highlights bucket name"
  type        = string
}

variable "raw_tracking_bucket_name" {
  description = "Raw tracking bucket name"
  type        = string
}

variable "dynamodb_table_name" {
  description = "DynamoDB match events table name"
  type        = string
}

variable "enable_worker_service" {
  description = "Whether to create the worker ECS service"
  type        = bool
  default     = false
}

variable "worker_cpu" {
  description = "Worker task CPU units"
  type        = number
  default     = 1024
}

variable "worker_memory" {
  description = "Worker task memory in MiB"
  type        = number
  default     = 2048
}

variable "worker_desired_count" {
  description = "Desired worker task count"
  type        = number
  default     = 0
}

variable "worker_min_capacity" {
  description = "Minimum worker task count"
  type        = number
  default     = 0
}

variable "worker_max_capacity" {
  description = "Maximum worker task count"
  type        = number
  default     = 2
}

variable "worker_log_retention_days" {
  description = "CloudWatch log retention for worker"
  type        = number
  default     = 14
}

variable "video_processing_queue_url" {
  description = "URL of the video processing jobs queue"
  type        = string
  default     = null
}

variable "video_processing_queue_arn" {
  description = "ARN of the video processing jobs queue"
  type        = string
  default     = null
}

variable "video_processing_queue_name" {
  description = "Name of the video processing jobs queue"
  type        = string
  default     = null
}

variable "status_callbacks_queue_url" {
  description = "URL of the match status callbacks queue"
  type        = string
  default     = null
}

variable "worker_polling_interval_seconds" {
  description = "Polling interval for worker SQS consumer"
  type        = number
  default     = 20
}