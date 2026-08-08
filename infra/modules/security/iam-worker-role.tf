data "aws_iam_policy_document" "worker_assume_role" {
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

resource "aws_iam_role" "worker_task" {
  name               = local.worker_task_role_name
  assume_role_policy = data.aws_iam_policy_document.worker_assume_role.json

  tags = merge(local.common_tags, {
    Name    = local.worker_task_role_name
    Service = "worker"
  })
}

data "aws_iam_policy_document" "worker_task_policy" {
  statement {
    sid    = "AllowConsumeVideoJobsQueue"
    effect = "Allow"
    actions = [
      "sqs:ChangeMessageVisibility",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage"
    ]
    resources = [local.video_jobs_queue_arn]
  }

  statement {
    sid    = "AllowSendStatusCallbacks"
    effect = "Allow"
    actions = [
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:SendMessage"
    ]
    resources = [local.status_callbacks_queue_arn]
  }

  statement {
    sid    = "AllowRawVideoRead"
    effect = "Allow"
    actions = [
      "s3:GetObject"
    ]
    resources = ["${var.raw_videos_bucket_arn}/*"]
  }

  statement {
    sid    = "AllowHightlightAndTrackingWrite"
    effect = "Allow"
    actions = [
      "s3:PutObject"
    ]
    resources = [
      "${var.processed_highlights_bucket_arn}/raw-clips/*",
      "${var.raw_tracking_data_bucket_arn}/*"
    ]
  }

  statement {
    sid    = "AllowDynamoDbMatchEventsWrite"
    effect = "Allow"
    actions = [
      "dynamodb:BatchWriteItem",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:Query",
      "dynamodb:UpdateItem"
    ]
    resources = [var.dynamodb_table_arn]
  }
}

resource "aws_iam_policy" "worker_task" {
  name   = "${local.name_prefix}-worker-task-policy"
  policy = data.aws_iam_policy_document.worker_task_policy.json

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-worker-task-policy"
    Service = "worker"
  })
}

resource "aws_iam_role_policy_attachment" "worker_task" {
  role       = aws_iam_role.worker_task.name
  policy_arn = aws_iam_policy.worker_task.arn
}
