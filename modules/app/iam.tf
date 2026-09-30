data "aws_caller_identity" "current" {}

# --- ECS task execution role (pulls images, reads secrets, writes logs) ---
resource "aws_iam_role" "execution" {
  name = "${local.name}-ecs-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow execution role to read the app secrets (for container `secrets` injection).
resource "aws_iam_role_policy" "execution_secrets" {
  name = "read-secrets"
  role = aws_iam_role.execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = [
        aws_secretsmanager_secret.app_key.arn,
        aws_secretsmanager_secret.db_password.arn,
        aws_secretsmanager_secret.shopify_client_id.arn,
        aws_secretsmanager_secret.shopify_client_secret.arn,
      ]
    }]
  })
}

# --- ECS task role (what the running app is allowed to do) ---
resource "aws_iam_role" "task" {
  name = "${local.name}-ecs-task"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

# App permissions: consume/produce the job queue, publish webhooks to SNS,
# and read from the webhook SQS queue.
resource "aws_iam_role_policy" "task_messaging" {
  name = "messaging"
  role = aws_iam_role.task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage",
          "sqs:GetQueueAttributes", "sqs:GetQueueUrl", "sqs:ChangeMessageVisibility"
        ]
        Resource = [
          aws_sqs_queue.jobs.arn, aws_sqs_queue.jobs_dlq.arn,
          aws_sqs_queue.webhooks.arn, aws_sqs_queue.webhooks_dlq.arn,
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = [aws_sns_topic.inbound_webhooks.arn]
      }
    ]
  })
}
