provider "aws" {
  region              = var.aws_region
  profile             = "st-voluong"
  allowed_account_ids = ["104091534817"]

  default_tags {
    tags = {
      Project     = "MatchLens"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
      CostCenter  = "matchlens-project"
    }
  }
}