variable "environment" {
  description = "Environment name: dev, stg, prod"
  type        = string
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "matchlens"
}

variable "vpc_id" {
  description = "VPC ID from network module"
  type        = string
}

variable "private_db_subnet_ids" {
  description = "Private DB subnet IDs from network module"
  type        = list(string)
}

variable "db_subnet_group_name" {
  description = "DB Subnet Group name, created in network module"
  type        = string
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "RDS allocated storage in DB (gp3)"
  type        = string
  default     = 20
}

variable "db_name" {
  description = "Default database name"
  type        = string
  default     = "matchlens"
}

variable "db_master_username" {
  description = "RDS Master username"
  type        = string
  default     = "matchlens_admin"
}

variable "multi_az" {
  description = "Enable Multi-AZ standby (dev = false, staging/prod = true)"
  type        = bool
  default     = false
}

variable "create_read_replica" {
  description = "Whether to create a physical Read Replica (dev = false, staging/prod = true)"
  type        = bool
  default     = false
}

variable "replica_instance_class" {
  description = "RDS Read Replica instance class"
  type        = string
  default     = "db.t3.small"
}