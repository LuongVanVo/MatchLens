resource "aws_s3_bucket_lifecycle_configuration" "raw_videos" {
  bucket = aws_s3_bucket.raw_videos.id

  rule {
    id     = "raw-videos-glacier-than-expire"
    status = "Enabled"

    # AWS Provider v5 bắt buộc phải có block filter
    filter {}

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    expiration {
      days = 90
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "raw_tracking_data" {
  bucket = aws_s3_bucket.raw_tracking_data.id

  rule {
    id     = "transition-to-glacier"
    status = "Enabled"

    filter {}

    transition {
      days          = 14
      storage_class = "GLACIER"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  rule {
    id     = "expire-after-7-days"
    status = "Enabled"

    filter {}

    expiration {
      days = 7
    }
  }
}

# [Q23 & Roadmap] Tự động xoá các video gốc trước transcode (raw-clips/) sau 7 ngày để tiết kiệm phí
resource "aws_s3_bucket_lifecycle_configuration" "processed_highlights" {
  bucket = aws_s3_bucket.processed_highlights.id

  rule {
    id     = "delete-raw-clips-after-7-days"
    status = "Enabled"

    filter {
      prefix = "raw-clips/"
    }

    expiration {
      days = 7
    }
  }
}