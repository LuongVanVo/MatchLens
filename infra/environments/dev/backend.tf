terraform {
  backend "s3" {
    bucket         = "matchlens-terraform-state-104091534817"
    key            = "environments/dev/terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "matchlens-terraform-locks"
    profile        = "st-voluong"
    use_lockfile   = true
    encrypt        = true
  }
}