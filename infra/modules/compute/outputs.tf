output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.this.name
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.this.arn
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.this.dns_name
}

output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.this.arn
}

output "alb_security_group_id" {
  description = "ALB security group ID"
  value       = aws_security_group.alb.id
}

output "ecs_security_group_id" {
  description = "ECS tasks security group ID"
  value       = aws_security_group.ecs.id
}

output "backend_service_name" {
  description = "Backend ECS service name"
  value       = aws_ecs_service.backend.name
}

output "backend_task_definition_arn" {
  description = "Backend ECS task definition ARN"
  value       = aws_ecs_task_definition.backend.arn
}

output "backend_target_group_arn" {
  description = "Backend ALB target group ARN"
  value       = aws_lb_target_group.backend.arn
}

output "worker_service_name" {
  description = "Worker ECS service name"
  value       = local.create_worker ? aws_ecs_service.worker[0].name : null
}

output "worker_task_definition_arn" {
  description = "Worker ECS task definition ARN"
  value       = local.create_worker ? aws_ecs_task_definition.worker[0].arn : null
}