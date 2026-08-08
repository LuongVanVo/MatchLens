data "aws_iam_policy_document" "glue_assume_role" {
  statement {
    sid     = "AllowGlueAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "glue_job" {
  name               = local.glue_job_role_name
  assume_role_policy = data.aws_iam_policy_document.glue_assume_role.json

  tags = merge(local.common_tags, {
    Name    = local.glue_job_role_name
    Service = "analytics"
  })
}

data "aws_iam_policy_document" "glue_job_policy" {
  statement {
    sid    = "AllowReadRawTrackingData"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      var.raw_tracking_data_bucket_arn,
      "${var.raw_tracking_data_bucket_arn}/*"
    ]
  }

  statement {
    sid    = "AllowWriteCuratedData"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject"
    ]
    resources = ["${var.curated_data_bucket_arn}/*"]
  }

  statement {
    sid    = "AllowAthenaResultsAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]
    resources = ["${var.athena_results_bucket_arn}/*"]
  }

  statement {
    sid    = "AllowGlueLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:*"]
  }
}

resource "aws_iam_policy" "glue_job" {
  name   = "${local.name_prefix}-glue-job-policy"
  policy = data.aws_iam_policy_document.glue_job_policy.json

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-glue-job-policy"
    Service = "analytics"
  })
}

resource "aws_iam_role_policy_attachment" "glue_job" {
  role       = aws_iam_role.glue_job.name
  policy_arn = aws_iam_policy.glue_job.arn
}