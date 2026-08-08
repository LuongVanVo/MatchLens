resource "aws_dynamodb_table" "match_events" {
  name         = "matchlens-${var.environment}-match-events"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "match_id"
  range_key    = "event_id"

  attribute {
    name = "match_id"
    type = "S"
  }

  attribute {
    name = "event_id"
    type = "S"
  }

  tags = {
    Name = "matchlens-${var.environment}-match-events"
  }
}