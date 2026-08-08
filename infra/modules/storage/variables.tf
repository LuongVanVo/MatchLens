variable "environment" {
  description = "Environment name: dev, stg, prod"
  type        = string
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "matchlens"
}
