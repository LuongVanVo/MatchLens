locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = "MatchLens"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner
    CostCenter  = "matchlens-project"
  }

  backend_container_name = "${local.name_prefix}-backend"
  worker_container_name  = "${local.name_prefix}-worker"

  backend_service_name = "${local.name_prefix}-backend-service"
  worker_service_name  = "${local.name_prefix}-worker-service"

  backend_task_family = "${local.name_prefix}-backend-task"
  worker_task_family  = "${local.name_prefix}-worker-task"

  cluster_name = "${local.name_prefix}-cluster"

  alb_name                = "${local.name_prefix}-alb"
  backend_target_group    = "${local.name_prefix}-backend-tg"
  alb_security_group_name = "${local.name_prefix}-alb-sg"
  ecs_security_group_name = "${local.name_prefix}-ecs-sg"

  create_worker = var.enable_worker_service
}