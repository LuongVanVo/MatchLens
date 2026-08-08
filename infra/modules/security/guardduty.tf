resource "aws_guardduty_detector" "this" {
  enable = true

  datasources {
    s3_logs {
      enable = true
    }
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-guardduty-detector"
    Service = "security"
  })
}