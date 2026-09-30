terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.60" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }

  backend "s3" {
    bucket       = "liquorpilot-consolidator-tfstate"
    key          = "prod/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true # native S3 state locking (no DynamoDB needed)
    encrypt      = true
  }
}
