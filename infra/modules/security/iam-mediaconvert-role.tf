# AWS MediaConvert Service
data "aws_iam_policy_document" "mediaconvert_service_assume_role" {
  statement {
    sid     = "AllowMediaConvertAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["mediaconvert.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "mediaconvert_service" {
  name               = local.mediaconvert_service_role_name
  assume_role_policy = data.aws_iam_policy_document.mediaconvert_service_assume_role.json

  tags = merge(local.common_tags, {
    Name    = local.mediaconvert_service_role_name
    Service = "messaging"
  })
}

data "aws_iam_policy_document" "mediaconvert_service_policy" {
  statement {
    sid    = "AllowReadRawClips"
    effect = "Allow"
    actions = [
      "s3:GetObject"
    ]
    resources = ["${var.processed_highlights_bucket_arn}/raw-clips/*"]
  }

  statement {
    sid    = "AllowWriteFinalHightlights"
    effect = "Allow"
    actions = [
      "s3:PutObject"
    ]
    resources = ["${var.processed_highlights_bucket_arn}/clips/*"]
  }
}

resource "aws_iam_policy" "mediaconvert_service" {
  name   = "${local.name_prefix}-mediaconvert-service-policy"
  policy = data.aws_iam_policy_document.mediaconvert_service_policy.json

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-mediaconvert-service-policy"
    Service = "messaging"
  })
}

resource "aws_iam_role_policy_attachment" "mediaconvert_service" {
  role       = aws_iam_role.mediaconvert_service.name
  policy_arn = aws_iam_policy.mediaconvert_service.arn
}

# MediaConvert Trigger Lambda
data "aws_iam_policy_document" "mediaconvert_trigger_assume_role" {
  statement {
    sid     = "AllowLambdaAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "mediaconvert_trigger_lambda" {
  name               = local.mediaconvert_trigger_role_name
  assume_role_policy = data.aws_iam_policy_document.mediaconvert_trigger_assume_role.json

  tags = merge(local.common_tags, {
    Name    = local.mediaconvert_trigger_role_name
    Service = "messaging"
  })
}

data "aws_iam_policy_document" "mediaconvert_trigger_lambda_policy" {
  statement {
    sid    = "AllowReadRawClips"
    effect = "Allow"
    actions = [
      "s3:GetObject"
    ]
    resources = ["${var.processed_highlights_bucket_arn}/raw-clips/*"]
  }

  # statement {
  #   sid    = "AllowWriteFinalHightlights"
  #   effect = "Allow"
  #   actions = [
  #     "s3:PutObject"
  #   ]
  #   resources = ["${var.processed_highlights_bucket_arn}/clips/*"]
  # }

  statement {
    sid    = "AllowMediaConvertJobManagement"
    effect = "Allow"
    actions = [
      "mediaconvert:CreateJob",
      "mediaconvert:GetJob",
      "mediaconvert:DescribeEndpoints"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowPassMediaConvertServiceRole"
    effect = "Allow"
    actions = [
      "iam:PassRole"
    ]
    resources = [aws_iam_role.mediaconvert_service.arn]
  }

  statement {
    sid    = "AllowWriteCloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:*"]
  }
}

resource "aws_iam_policy" "mediaconvert_trigger_lambda" {
  name   = "${local.name_prefix}-mediaconvert-trigger-lambda-policy"
  policy = data.aws_iam_policy_document.mediaconvert_trigger_lambda_policy.json

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-mediaconvert-trigger-lambda-policy"
    Service = "messaging"
  })
}

resource "aws_iam_role_policy_attachment" "mediaconvert_trigger_lambda" {
  role       = aws_iam_role.mediaconvert_trigger_lambda.name
  policy_arn = aws_iam_policy.mediaconvert_trigger_lambda.arn
}