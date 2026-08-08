output "raw_videos_bucket_name" {
  value = aws_s3_bucket.raw_videos.id
}

output "raw_videos_bucket_arn" {
  value = aws_s3_bucket.raw_videos.arn
}

output "processed_highlights_bucket_name" {
  value = aws_s3_bucket.processed_highlights.id
}

output "processed_highlights_bucket_arn" {
  value = aws_s3_bucket.processed_highlights.arn
}

output "raw_tracking_bucket_name" {
  value = aws_s3_bucket.raw_tracking_data.id
}

output "raw_tracking_bucket_arn" {
  value = aws_s3_bucket.raw_tracking_data.arn
}

output "curated_data_bucket_name" {
  value = aws_s3_bucket.curated_data.id
}

output "curated_data_bucket_arn" {
  value = aws_s3_bucket.curated_data.arn
}

output "athena_results_bucket_name" {
  value = aws_s3_bucket.athena_results.id
}

output "athena_results_bucket_arn" {
  value = aws_s3_bucket.athena_results.arn
}