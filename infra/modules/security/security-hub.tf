resource "aws_securityhub_account" "this" {}

resource "aws_securityhub_standards_subscription" "aws_foundational" {
  standards_arn = "arn:${local.partition}:securityhub:${local.region}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.this]
}

# resource "aws_securityhub_finding_aggregator" "this" {
#   linking_mode = "SPECIFIED_REGIONS"
#   specified_regions = [ var.aws_region ]
# }