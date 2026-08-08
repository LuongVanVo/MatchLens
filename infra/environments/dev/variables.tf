variable "environment" {
  description = "Environment name: dev, staging, prod"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-1"
}

variable "owner" {
  description = "Owner tag value (responsible person)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "az_count" {
  description = "Number of availability zones"
  type        = number
  default     = 2
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (per AZ)"
  type        = list(string)
}

variable "private_app_subnet_cidrs" {
  description = "CIDR blocks for private app subnets (per AZ)"
  type        = list(string)
}

variable "private_db_subnet_cidrs" {
  description = "CIDR blocks for private db subnets (per AZ)"
  type        = list(string)
}

variable "nat_instance_count" {
  description = "Number of NAT instances (dev = 1)"
  type        = number
  default     = 1
}

variable "database_url_master" {
  type      = string
  sensitive = true
}

variable "database_url_replica" {
  type      = string
  sensitive = true
}

variable "jwt_access_public_key" {
  type      = string
  sensitive = true
}

variable "jwt_access_private_key" {
  type      = string
  sensitive = true
}

variable "jwt_refresh_private_key" {
  type      = string
  sensitive = true
}

variable "backend_image_uri" {
  description = "ECR image URI for backend service"
  type        = string
}

variable "worker_image_uri" {
  description = "ECR image URI for worker service"
  type        = string
  default     = null
}