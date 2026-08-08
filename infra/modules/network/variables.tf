variable "environment" {
  description = "Environment name: dev, staging, prod"
  type        = string
}

variable "aws_region" {
  description = "AWS region for MatchLens"
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "matchlens"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "az_count" {
  description = "Number of availability zones to use"
  type        = number
  default     = 2
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "private_app_subnet_cidrs" {
  description = "CIDR blocks for private app subnets"
  type        = list(string)
}

variable "private_db_subnet_cidrs" {
  description = "CIDR block for private db subnets"
  type        = list(string)
}

variable "nat_instance_count" {
  description = "Number of NAT Instances"
  type        = number
  default     = 1
}
