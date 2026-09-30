variable "environment" {
  description = "Environment name (qa | prod). Used as a resource name prefix."
  type        = string
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "name_prefix" {
  description = "Base name for resources, e.g. lp-consolidator."
  type        = string
  default     = "lp-consolidator"
}

# --- Networking ---
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "az_count" {
  type    = number
  default = 2
}

# --- DNS / TLS ---
variable "route53_zone_id" {
  description = "Hosted zone ID for the root domain (e.g. liquorpilot.com)."
  type        = string
}

variable "app_domain" {
  description = "Full domain for the dashboard/API ALB, e.g. qa-consolidator.liquorpilot.com."
  type        = string
}

variable "webhook_domain" {
  description = "Full domain for the inbound webhook service, e.g. qa-webhooks.liquorpilot.com."
  type        = string
}

# --- Database ---
variable "db_instance_class" {
  type    = string
  default = "db.t4g.small"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "db_multi_az" {
  type    = bool
  default = false
}

variable "db_name" {
  type    = string
  default = "consolidator"
}

variable "db_username" {
  type    = string
  default = "consolidator"
}

# --- Container images (pushed to the ECR repos created here) ---
variable "api_image_tag" {
  type    = string
  default = "latest"
}

variable "webhook_image_tag" {
  type    = string
  default = "latest"
}

# --- Service sizing ---
variable "api_cpu" {
  type    = number
  default = 512
}
variable "api_memory" {
  type    = number
  default = 1024
}
variable "api_desired_count" {
  type    = number
  default = 1
}
variable "worker_desired_count" {
  type    = number
  default = 1
}

# --- App secrets (set per-env; stored in Secrets Manager, never in state as plaintext when possible) ---
variable "shopify_client_id" {
  type      = string
  default   = ""
  sensitive = true
}
variable "shopify_client_secret" {
  type      = string
  default   = ""
  sensitive = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
