data "aws_iam_policy_document" "status_updater_assume_role" {
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

resource "aws_iam_role" "status_updater_lambda" {
  name               = local.status_updater_lambda_role_name
  assume_role_policy = data.aws_iam_policy_document.status_updater_assume_role.json

  tags = merge(local.common_tags, {
    Name    = local.status_updater_lambda_role_name
    Service = "messaging"
  })
}

data "aws_iam_policy_document" "status_updater_lambda_policy" {
  statement {
    sid    = "AllowConsumeStatusCallbacksQueue"
    effect = "Allow"
    actions = [
      "sqs:ChangeMessageVisibility",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage"
    ]
    resources = [local.status_callbacks_queue_arn]
  }

  statement {
    sid    = "AllowDbSecretRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    resources = [var.db_secret_arn]
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

resource "aws_iam_policy" "status_updater_lambda" {
  name   = "${local.name_prefix}-status-updater-lambda-policy"
  policy = data.aws_iam_policy_document.status_updater_lambda_policy.json

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-status-updater-lambda-policy"
    Service = "messaging"
  })
}

resource "aws_iam_role_policy_attachment" "status_updater_lambda" {
  role       = aws_iam_role.status_updater_lambda.name
  policy_arn = aws_iam_policy.status_updater_lambda.arn
}

resource "aws_iam_role_policy_attachment" "status_updater_vpc_access" {
  role       = aws_iam_role.status_updater_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}