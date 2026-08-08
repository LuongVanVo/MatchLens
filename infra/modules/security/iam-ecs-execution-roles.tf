data "aws_iam_policy_document" "ecs_task_execution_assume_role" {
  statement {
    sid    = "AllowEcsTasksAssumeRole"
    effect = "Allow"

    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backend_task_execution" {
  name               = local.backend_task_execution_role_name
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_assume_role.json

  tags = merge(local.common_tags, {
    Name = local.backend_task_execution_role_name
  })
}

resource "aws_iam_role_policy_attachment" "backend_task_execution_amazon_ecs_task_execution_role_policy" {
  role       = aws_iam_role.backend_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "worker_task_execution" {
  name               = local.worker_task_execution_role_name
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_assume_role.json

  tags = merge(local.common_tags, {
    Name = local.worker_task_execution_role_name
  })
}

resource "aws_iam_role_policy_attachment" "worker_task_execution_amazon_ecs_task_execution_role_policy" {
  role       = aws_iam_role.worker_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}