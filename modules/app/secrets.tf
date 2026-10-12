# Laravel APP_KEY: "base64:" + 32 random bytes. One value, shared by every task.
resource "random_id" "app_key" {
  byte_length = 32
}

locals {
  app_key = "base64:${random_id.app_key.b64_std}"
}

resource "aws_secretsmanager_secret" "app_key" {
  name = "${local.name}/APP_KEY"
  tags = local.tags
}
resource "aws_secretsmanager_secret_version" "app_key" {
  secret_id     = aws_secretsmanager_secret.app_key.id
  secret_string = local.app_key
}

resource "aws_secretsmanager_secret" "db_password" {
  name = "${local.name}/DB_PASSWORD"
  tags = local.tags
}
resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db.result
}

resource "aws_secretsmanager_secret" "shopify_client_id" {
  name = "${local.name}/SHOPIFY_APP_CLIENT_ID"
  tags = local.tags
}
resource "aws_secretsmanager_secret_version" "shopify_client_id" {
  secret_id = aws_secretsmanager_secret.shopify_client_id.id
  # Secrets Manager rejects an empty value, so fall back to a placeholder that
  # you overwrite in Secrets Manager (or via TF_VAR on first apply).
  secret_string = var.shopify_client_id != "" ? var.shopify_client_id : "REPLACE_ME"
  # Value is managed in Secrets Manager afterwards; later applies won't clobber it.
  lifecycle { ignore_changes = [secret_string] }
}

resource "aws_secretsmanager_secret" "shopify_client_secret" {
  name = "${local.name}/SHOPIFY_APP_CLIENT_SECRET"
  tags = local.tags
}
resource "aws_secretsmanager_secret_version" "shopify_client_secret" {
  secret_id     = aws_secretsmanager_secret.shopify_client_secret.id
  secret_string = var.shopify_client_secret != "" ? var.shopify_client_secret : "REPLACE_ME"
  lifecycle { ignore_changes = [secret_string] }
}
