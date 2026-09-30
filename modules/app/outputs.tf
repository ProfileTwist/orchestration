output "app_url" {
  value = "https://${var.app_domain}"
}

output "webhook_url" {
  value = "https://${var.webhook_domain}"
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "db_endpoint" {
  value = aws_db_instance.this.address
}

output "ecr_api_url" {
  value = aws_ecr_repository.api.repository_url
}

output "ecr_web_url" {
  value = aws_ecr_repository.web.repository_url
}

output "ecr_webhook_url" {
  value = aws_ecr_repository.webhook.repository_url
}

output "sqs_jobs_queue" {
  value = aws_sqs_queue.jobs.name
}

output "sns_inbound_topic_arn" {
  value = aws_sns_topic.inbound_webhooks.arn
}

output "ecs_cluster" {
  value = aws_ecs_cluster.this.name
}
