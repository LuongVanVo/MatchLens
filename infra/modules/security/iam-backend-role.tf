data "aws_iam_policy_document" "backend_assume_role" {
  statement {
    sid     = "AllowEcsTasksAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backend_task" {
  name               = local.backend_task_role_name
  assume_role_policy = data.aws_iam_policy_document.backend_assume_role.json

  tags = merge(local.common_tags, {
    Name    = local.backend_task_role_name
    Service = "backend"
  })
}

data "aws_iam_policy_document" "backend_task_policy" {
  statement {
    sid    = "AllowRawVideoPresign"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]
    resources = ["${var.raw_videos_bucket_arn}/*"]
  }

  statement {
    sid    = "AllowProcessedHighlightsRead"
    effect = "Allow"
    actions = [
      "s3:GetObject"
    ]
    resources = ["${var.processed_highlights_bucket_arn}/*"]
  }

  statement {
    sid    = "AllowTrackingDataRead"
    effect = "Allow"
    actions = [
      "s3:GetObject"
    ]
    resources = ["${var.raw_tracking_data_bucket_arn}/*"]
  }

  statement {
    sid    = "AllowCuratedDataRead"
    effect = "Allow"
    actions = [
      "s3:GetObject"
    ]
    resources = ["${var.curated_data_bucket_arn}/*"]
  }

  statement {
    sid    = "AllowDynamoDBMatchEventsRead"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:Scan"
    ]
    resources = [var.dynamodb_table_arn]
  }

  statement {
    sid    = "AllowDbSecretRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    resources = [
      var.db_secret_arn,
      aws_secretsmanager_secret.jwt_keypair.arn,
      aws_secretsmanager_secret.cloudfront_signing_key.arn
    ]
  }

  statement {
    sid    = "AllowAthenaQueryExecution"
    effect = "Allow"
    actions = [
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:StartQueryExecution",
      "athena:StopQueryExecution"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowAthenaResultsBucketAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]
    resources = ["${var.athena_results_bucket_arn}/*"]
  }
}

resource "aws_iam_policy" "backend_task" {
  name   = "${local.name_prefix}-backend-task-policy"
  policy = data.aws_iam_policy_document.backend_task_policy.json

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-backend-task-policy"
    Service = "backend"
  })
}

resource "aws_iam_role_policy_attachment" "backend_task" {
  role       = aws_iam_role.backend_task.name
  policy_arn = aws_iam_policy.backend_task.arn
}
