resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-github-oidc-provider"
    Service = "cicd"
  })
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    sid     = "AllowGithubActionsAssumeRoleWithOidc"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.github_oidc_subject]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = local.github_actions_role_name
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json

  tags = merge(local.common_tags, {
    Name    = local.github_actions_role_name
    Service = "cicd"
  })
}

data "aws_iam_policy_document" "github_actions_policy" {
  statement {
    sid    = "AllowEcrPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:GetAuthorizationToken",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowEcsDeploymentRead"
    effect = "Allow"
    actions = [
      "ecs:DescribeClusters",
      "ecs:DescribeServices",
      "ecs:DescribeTaskDefinition",
      "ecs:ListTasks"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowEcsDeploymentWrite"
    effect = "Allow"
    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:UpdateService"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowPassEcsTaskRoles"
    effect = "Allow"
    actions = [
      "iam:PassRole"
    ]
    resources = [
      aws_iam_role.backend_task.arn,
      aws_iam_role.worker_task.arn
    ]
  }

  statement {
    sid    = "AllowReadSecretsForDeployment"
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue"
    ]
    resources = [
      var.db_secret_arn,
      aws_secretsmanager_secret.jwt_keypair.arn,
      aws_secretsmanager_secret.cloudfront_signing_key.arn
    ]
  }
}

resource "aws_iam_policy" "github_actions" {
  name   = "${local.name_prefix}-github-actions-policy"
  policy = data.aws_iam_policy_document.github_actions_policy.json

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-github-actions-policy"
    Service = "cicd"
  })
}

resource "aws_iam_role_policy_attachment" "github_actions" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions.arn
}