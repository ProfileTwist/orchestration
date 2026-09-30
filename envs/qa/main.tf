variable "region" {
  type    = string
  default = "us-east-1"
}

variable "root_domain" {
  type    = string
  default = "liquorpilot.com"
}

# Provide via TF_VAR_shopify_client_id / _secret or a git-ignored *.auto.tfvars —
# never commit real values.
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

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      ManagedBy   = "terraform"
      Project     = "shopify-consolidator"
      Environment = "qa"
    }
  }
}

data "aws_route53_zone" "root" {
  name = var.root_domain
}

module "app" {
  source = "../../modules/app"

  environment     = "qa"
  region          = var.region
  route53_zone_id = data.aws_route53_zone.root.zone_id
  app_domain      = "qa-consolidator.${var.root_domain}"
  webhook_domain  = "qa-webhooks.${var.root_domain}"

  db_instance_class = "db.t4g.small"
  db_multi_az       = false

  api_desired_count    = 1
  worker_desired_count = 1

  shopify_client_id     = var.shopify_client_id
  shopify_client_secret = var.shopify_client_secret
}

output "app_url" { value = module.app.app_url }
output "webhook_url" { value = module.app.webhook_url }
output "db_endpoint" { value = module.app.db_endpoint }
output "ecr_api_url" { value = module.app.ecr_api_url }
output "ecr_web_url" { value = module.app.ecr_web_url }
output "ecr_webhook_url" { value = module.app.ecr_webhook_url }
output "ecs_cluster" { value = module.app.ecs_cluster }
