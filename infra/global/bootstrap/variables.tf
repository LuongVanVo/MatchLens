variable "aws_region" {
  description = "AWS region where the entire MatchLens project is deployed"
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Name of the project, used as a prefix for all resource"
  type        = string
  default     = "matchlens"
}

variable "owner" {
  description = "Owner of the project - tag owner"
  type        = string
  default     = "voluongdev"
}