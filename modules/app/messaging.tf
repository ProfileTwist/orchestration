# --- Laravel job queue (QUEUE_CONNECTION=sqs) ---
resource "aws_sqs_queue" "jobs_dlq" {
  name = "${local.name}-jobs-dlq"
  tags = local.tags
}

resource "aws_sqs_queue" "jobs" {
  name                       = "${local.name}-jobs"
  visibility_timeout_seconds = 120
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.jobs_dlq.arn
    maxReceiveCount     = 5
  })
  tags = local.tags
}

# --- Inbound webhook fan-out: SNS topic -> SQS consumer ---
resource "aws_sns_topic" "inbound_webhooks" {
  name = "${local.name}-inbound-webhooks"
  tags = local.tags
}

resource "aws_sqs_queue" "webhooks_dlq" {
  name = "${local.name}-webhooks-dlq"
  tags = local.tags
}

resource "aws_sqs_queue" "webhooks" {
  name                       = "${local.name}-webhooks-consumer"
  visibility_timeout_seconds = 120
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.webhooks_dlq.arn
    maxReceiveCount     = 5
  })
  tags = local.tags
}

resource "aws_sns_topic_subscription" "webhooks" {
  topic_arn            = aws_sns_topic.inbound_webhooks.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.webhooks.arn
  raw_message_delivery = true
}

# Allow the SNS topic to deliver to the SQS queue.
resource "aws_sqs_queue_policy" "webhooks" {
  queue_url = aws_sqs_queue.webhooks.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.webhooks.arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_sns_topic.inbound_webhooks.arn } }
    }]
  })
}
