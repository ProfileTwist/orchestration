resource "aws_ecs_cluster" "this" {
  name = local.name
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  tags = local.tags
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${local.name}"
  retention_in_days = var.environment == "prod" ? 30 : 14
  tags              = local.tags
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  app_url    = "https://${var.app_domain}"

  api_image     = "${aws_ecr_repository.api.repository_url}:${var.api_image_tag}"
  web_image     = "${aws_ecr_repository.web.repository_url}:${var.api_image_tag}"
  webhook_image = "${aws_ecr_repository.webhook.repository_url}:${var.webhook_image_tag}"

  # Plain env shared by the Laravel API/queue/scheduler containers.
  laravel_env = [
    { name = "APP_ENV", value = var.environment == "prod" ? "production" : "staging" },
    { name = "APP_DEBUG", value = "false" },
    { name = "APP_URL", value = local.app_url },
    { name = "LOG_CHANNEL", value = "stderr" },
    { name = "DB_CONNECTION", value = "mysql" },
    { name = "DB_HOST", value = aws_db_instance.this.address },
    { name = "DB_PORT", value = "3306" },
    { name = "DB_DATABASE", value = var.db_name },
    { name = "DB_USERNAME", value = var.db_username },
    { name = "CACHE_STORE", value = "database" },
    { name = "SESSION_DRIVER", value = "database" },
    { name = "QUEUE_CONNECTION", value = "sqs" },
    { name = "AWS_DEFAULT_REGION", value = var.region },
    { name = "SQS_PREFIX", value = "https://sqs.${var.region}.amazonaws.com/${local.account_id}" },
    { name = "SQS_QUEUE", value = aws_sqs_queue.jobs.name },
    { name = "SHOPIFY_DRIVER", value = "http" },
    { name = "SHOPIFY_SCOPES", value = "read_orders,read_all_orders,read_shopify_payments_payouts,read_products,write_products,write_draft_orders" },
    { name = "SHOPIFY_REDIRECT_URI", value = "${local.app_url}/api/shopify/callback" },
    { name = "SHOPIFY_FRONTEND_URL", value = local.app_url },
    { name = "SHOPIFY_WEBHOOK_URL", value = "https://${var.webhook_domain}" },
  ]

  laravel_secrets = [
    { name = "APP_KEY", valueFrom = aws_secretsmanager_secret.app_key.arn },
    { name = "DB_PASSWORD", valueFrom = aws_secretsmanager_secret.db_password.arn },
    { name = "SHOPIFY_APP_CLIENT_ID", valueFrom = aws_secretsmanager_secret.shopify_client_id.arn },
    { name = "SHOPIFY_APP_CLIENT_SECRET", valueFrom = aws_secretsmanager_secret.shopify_client_secret.arn },
  ]

  webhook_env = [
    { name = "APP_ENV", value = var.environment == "prod" ? "production" : "staging" },
    { name = "APP_DEBUG", value = "false" },
    { name = "LOG_CHANNEL", value = "stderr" },
    { name = "AWS_DEFAULT_REGION", value = var.region },
    { name = "SNS_TOPIC_ARN", value = aws_sns_topic.inbound_webhooks.arn },
    { name = "SHOPIFY_WEBHOOK_SKIP_VERIFY", value = "false" },
  ]
  webhook_secrets = [
    { name = "APP_KEY", valueFrom = aws_secretsmanager_secret.app_key.arn },
    { name = "SHOPIFY_WEBHOOK_SECRET", valueFrom = aws_secretsmanager_secret.shopify_client_secret.arn },
  ]

  log_opts = {
    "awslogs-group"         = aws_cloudwatch_log_group.this.name
    "awslogs-region"        = var.region
    "awslogs-stream-prefix" = "ecs"
  }
}

# Helper to define a Fargate task definition + service.
# --- API (serves the REST API over HTTP on :80) ---
resource "aws_ecs_task_definition" "api" {
  family                   = "${local.name}-api"
  requires_compatibilities = ["FARGATE"]
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }
  network_mode       = "awsvpc"
  cpu                = var.api_cpu
  memory             = var.api_memory
  execution_role_arn = aws_iam_role.execution.arn
  task_role_arn      = aws_iam_role.task.arn
  container_definitions = jsonencode([{
    name             = "api"
    image            = local.api_image
    essential        = true
    portMappings     = [{ containerPort = 80 }]
    environment      = local.laravel_env
    secrets          = local.laravel_secrets
    logConfiguration = { logDriver = "awslogs", options = local.log_opts }
  }])
  tags = local.tags
}

resource "aws_ecs_service" "api" {
  name            = "${local.name}-api"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.api_desired_count
  launch_type     = "FARGATE"
  network_configuration {
    subnets         = aws_subnet.private[*].id
    security_groups = [aws_security_group.ecs.id]
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = 80
  }
  depends_on = [aws_lb_listener.https]
  tags       = local.tags
}

# --- Web (SPA static, HTTP on :80) ---
resource "aws_ecs_task_definition" "web" {
  family                   = "${local.name}-web"
  requires_compatibilities = ["FARGATE"]
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }
  network_mode       = "awsvpc"
  cpu                = 256
  memory             = 512
  execution_role_arn = aws_iam_role.execution.arn
  task_role_arn      = aws_iam_role.task.arn
  container_definitions = jsonencode([{
    name             = "web"
    image            = local.web_image
    essential        = true
    portMappings     = [{ containerPort = 80 }]
    logConfiguration = { logDriver = "awslogs", options = local.log_opts }
  }])
  tags = local.tags
}

resource "aws_ecs_service" "web" {
  name            = "${local.name}-web"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    subnets         = aws_subnet.private[*].id
    security_groups = [aws_security_group.ecs.id]
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.web.arn
    container_name   = "web"
    container_port   = 80
  }
  depends_on = [aws_lb_listener.https]
  tags       = local.tags
}

# --- Queue worker (no ALB) ---
resource "aws_ecs_task_definition" "queue" {
  family                   = "${local.name}-queue"
  requires_compatibilities = ["FARGATE"]
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }
  network_mode       = "awsvpc"
  cpu                = 512
  memory             = 1024
  execution_role_arn = aws_iam_role.execution.arn
  task_role_arn      = aws_iam_role.task.arn
  container_definitions = jsonencode([{
    name             = "queue"
    image            = local.api_image
    essential        = true
    command          = ["php", "artisan", "queue:work", "--tries=3", "--backoff=30", "--timeout=90"]
    environment      = local.laravel_env
    secrets          = local.laravel_secrets
    logConfiguration = { logDriver = "awslogs", options = local.log_opts }
  }])
  tags = local.tags
}

resource "aws_ecs_service" "queue" {
  name            = "${local.name}-queue"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.queue.arn
  desired_count   = var.worker_desired_count
  launch_type     = "FARGATE"
  network_configuration {
    subnets         = aws_subnet.private[*].id
    security_groups = [aws_security_group.ecs.id]
  }
  tags = local.tags
}

# --- Scheduler (sub-minute; runs schedule:work continuously) ---
resource "aws_ecs_task_definition" "scheduler" {
  family                   = "${local.name}-scheduler"
  requires_compatibilities = ["FARGATE"]
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }
  network_mode       = "awsvpc"
  cpu                = 256
  memory             = 512
  execution_role_arn = aws_iam_role.execution.arn
  task_role_arn      = aws_iam_role.task.arn
  container_definitions = jsonencode([{
    name             = "scheduler"
    image            = local.api_image
    essential        = true
    command          = ["php", "artisan", "schedule:work"]
    environment      = local.laravel_env
    secrets          = local.laravel_secrets
    logConfiguration = { logDriver = "awslogs", options = local.log_opts }
  }])
  tags = local.tags
}

resource "aws_ecs_service" "scheduler" {
  name            = "${local.name}-scheduler"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.scheduler.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    subnets         = aws_subnet.private[*].id
    security_groups = [aws_security_group.ecs.id]
  }
  tags = local.tags
}

# --- Inbound webhook service (HTTP on :80) ---
resource "aws_ecs_task_definition" "webhook" {
  family                   = "${local.name}-webhook"
  requires_compatibilities = ["FARGATE"]
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }
  network_mode       = "awsvpc"
  cpu                = 256
  memory             = 512
  execution_role_arn = aws_iam_role.execution.arn
  task_role_arn      = aws_iam_role.task.arn
  container_definitions = jsonencode([{
    name             = "webhook"
    image            = local.webhook_image
    essential        = true
    portMappings     = [{ containerPort = 80 }]
    environment      = local.webhook_env
    secrets          = local.webhook_secrets
    logConfiguration = { logDriver = "awslogs", options = local.log_opts }
  }])
  tags = local.tags
}

resource "aws_ecs_service" "webhook" {
  name            = "${local.name}-webhook"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.webhook.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    subnets         = aws_subnet.private[*].id
    security_groups = [aws_security_group.ecs.id]
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.webhook.arn
    container_name   = "webhook"
    container_port   = 80
  }
  depends_on = [aws_lb_listener.https]
  tags       = local.tags
}
