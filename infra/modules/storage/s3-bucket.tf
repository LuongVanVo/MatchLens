locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "aws_s3_bucket" "raw_videos" {
  bucket        = "${local.name_prefix}-raw-videos"
  force_destroy = var.environment == "dev" ? true : false
}

resource "aws_s3_bucket" "processed_highlights" {
  bucket        = "${local.name_prefix}-processed-highlights"
  force_destroy = var.environment == "dev" ? true : false
}

resource "aws_s3_bucket" "raw_tracking_data" {
  bucket        = "${local.name_prefix}-raw-tracking-data"
  force_destroy = var.environment == "dev" ? true : false
}

resource "aws_s3_bucket" "curated_data" {
  bucket        = "${local.name_prefix}-curated-data"
  force_destroy = var.environment == "dev" ? true : false
}

resource "aws_s3_bucket" "athena_results" {
  bucket        = "${local.name_prefix}-athena-results"
  force_destroy = var.environment == "dev" ? true : false
}

# Gom nhóm để áp dụng chính sách chung
locals {
  all_buckets = {
    raw_videos           = aws_s3_bucket.raw_videos.id
    processed_highlights = aws_s3_bucket.processed_highlights.id
    raw_tracking_data    = aws_s3_bucket.raw_tracking_data.id
    curated_data         = aws_s3_bucket.curated_data.id
    athena_results       = aws_s3_bucket.athena_results.id
  }
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = local.all_buckets

  bucket = each.value
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = local.all_buckets

  bucket = each.value

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = local.all_buckets

  bucket = each.value

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}