output "rds_master_endpoint" {
  value = aws_db_instance.master.endpoint
}

output "rds_replica_endpoint" {
  value = var.create_read_replica ? aws_db_instance.replica[0].endpoint : aws_db_instance.master.endpoint
}

output "rds_secret_arn" {
  value = aws_secretsmanager_secret.db_credentials.arn
}

output "rds_security_group_id" {
  value = aws_security_group.rds.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.match_events.name
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.match_events.arn
}