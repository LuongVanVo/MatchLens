data "aws_iam_policy_document" "dispatcher_assume_role" {
  statement {
    sid    = "AllowLambdaAssumeRole"
    effect = "Allow"
    actions = [
      "sts:AssumeRole"
    ]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dispatcher_lambda" {
  name               = local.dispatcher_lambda_role_name
  assume_role_policy = data.aws_iam_policy_document.dispatcher_assume_role.json

  tags = merge(local.common_tags, {
    Name    = local.dispatcher_lambda_role_name
    Service = "messaging"
  })
}

data "aws_iam_policy_document" "dispatcher_task_policy" {
  statement {
    sid    = "AllowReadUploadedVideoMetadata"
    effect = "Allow"
    actions = [
      "s3:GetObject"
    ]
    resources = ["${var.raw_videos_bucket_arn}/*"]
  }

  statement {
    sid    = "AllowSendVideoJobsQueue"
    effect = "Allow"
    actions = [
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:SendMessage"
    ]
    resources = [local.video_jobs_queue_arn]
  }

  statement {
    sid    = "AllowSendStatusCallbacksQueue"
    effect = "Allow"
    actions = [
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:SendMessage"
    ]
    resources = [local.status_callbacks_queue_arn]
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

resource "aws_iam_policy" "dispatcher_lambda" {
  name   = "${local.name_prefix}-dispatcher-lambda-policy"
  policy = data.aws_iam_policy_document.dispatcher_task_policy.json

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-dispatcher-lambda-policy"
    Service = "messaging"
  })
}

resource "aws_iam_role_policy_attachment" "dispatcher_lambda" {
  role       = aws_iam_role.dispatcher_lambda.name
  policy_arn = aws_iam_policy.dispatcher_lambda.arn
}