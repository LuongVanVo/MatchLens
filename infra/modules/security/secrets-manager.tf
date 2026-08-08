resource "aws_secretsmanager_secret" "jwt_keypair" {
  name_prefix             = "${local.jwt_key_secret_name}-"
  description             = "JWT RS256 keypair for ${var.environment} backend auth"
  recovery_window_in_days = var.environment == "prod" ? 30 : 0

  tags = merge(local.common_tags, {
    Name               = local.jwt_key_secret_name
    Service            = "backend"
    DataClassification = "confidential"
    Backup             = "true"
  })
}

resource "aws_secretsmanager_secret" "cloudfront_signing_key" {
  name_prefix             = "${local.cloudfront_signing_secret_name}-"
  description             = "Cloudfront signing key reference for ${var.environment}"
  recovery_window_in_days = var.environment == "prod" ? 30 : 0

  tags = merge(local.common_tags, {
    Name               = local.cloudfront_signing_secret_name
    Service            = "storage"
    DataClassification = "confidential"
    Backup             = "true"
  })
}