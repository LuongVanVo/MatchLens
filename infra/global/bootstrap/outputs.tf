output "state_bucket_name" {
  description = "Name of S3 Bucket save remote state - used in backend.tf of all environment"
  value       = aws_s3_bucket.terraform_state.bucket
}

output "state_bucket_arn" {
  value = aws_s3_bucket.terraform_state.arn
}

output "lock_table_name" {
  description = "Name of DynamoDB Table Name lock state - used in backend.tf of all environment"
  value       = aws_dynamodb_table.terraform_locks.name
}