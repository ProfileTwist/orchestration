# Orchestration — Shopify Consolidation App (Terraform)

Deploys the Shopify consolidation app to AWS in two isolated environments, **qa**
and **prod**, each with its **own VPC, RDS MySQL, ECS cluster, ALB, SQS/SNS, and
secrets**. Region: **us-east-1**, single account.

```
devops/orchestration/
├── bootstrap/            # one-time: S3 state bucket (state + native locking)
├── modules/app/          # the reusable stack (network, rds, ecs, alb, sqs/sns, …)
└── envs/
    ├── qa/               # qa-consolidator.liquorpilot.com  /  qa-webhooks…
    └── prod/             # consolidator.liquorpilot.com     /  webhooks…
```

## What gets created per environment

- **VPC** (2 AZs, public + private subnets, 1 NAT)
- **RDS MySQL 8.4** (private; qa small/single-AZ, prod larger/multi-AZ)
- **ECS Fargate** cluster + 5 services: `api`, `web`, `queue`, `scheduler`, `webhook`
- **ALB** (HTTPS via ACM) — `app_domain` → web (SPA) + `/api/*` → api; `webhook_domain` → webhook
- **SQS** job queue (+DLQ) and **SNS→SQS** webhook chain (+DLQ)
- **Secrets Manager** — `APP_KEY` (generated, shared), DB password, Shopify creds
- **ECR** repos: `<env>-api`, `<env>-web`, `<env>-webhook`
- **Route 53** records + ACM DNS validation under the existing `liquorpilot.com` zone

## Prerequisites

- Terraform ≥ 1.6, AWS CLI, Docker
- AWS credentials (an admin/deploy role) for the target account
- The `liquorpilot.com` **Route 53 hosted zone** must already exist
- The Shopify app **Client ID/Secret** (passed as TF vars, stored in Secrets Manager)

## 1. Bootstrap remote state (once per account)

```bash
cd bootstrap
terraform init && terraform apply
# creates: s3 bucket liquorpilot-consolidator-tfstate (native S3 locking, no DynamoDB)
```

## 2. Deploy an environment

```bash
cd envs/qa            # or envs/prod
terraform init
export TF_VAR_shopify_client_id=xxxx
export TF_VAR_shopify_client_secret=xxxx     # keep these out of git
terraform plan
terraform apply
```

ACM cert validation + DNS are automatic (the hosted zone already exists). On the
first apply the ECS services come up **before** images exist, so their tasks will
restart until you push images (step 3).

## 3. Build & push images to ECR

All three services serve HTTP on :80. `api` + `webhook` use **`Dockerfile.prod`**
(FrankenPHP); `web` uses its existing nginx `Dockerfile`. Build from the app repo
(`cloud/shopify_consolidation_app`):

```bash
ENV=qa                # or prod
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
ECR=$ACCOUNT.dkr.ecr.$REGION.amazonaws.com
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR

# api (FrankenPHP, :80) — also used by queue/scheduler
docker build --platform linux/arm64 -f api/Dockerfile.prod -t $ECR/lp-consolidator-$ENV-api:latest ./api
docker push $ECR/lp-consolidator-$ENV-api:latest

# webhook (FrankenPHP, :80)
docker build --platform linux/arm64 -f inbound-webhook-api/Dockerfile.prod -t $ECR/lp-consolidator-$ENV-webhook:latest ./inbound-webhook-api
docker push $ECR/lp-consolidator-$ENV-webhook:latest

# web (nginx SPA, :80)
docker build --platform linux/arm64 -f web/Dockerfile.prod -t $ECR/lp-consolidator-$ENV-web:latest ./web
docker push $ECR/lp-consolidator-$ENV-web:latest

# roll the services onto the new images
for svc in api web webhook queue scheduler; do
  aws ecs update-service --cluster lp-consolidator-$ENV --service lp-consolidator-$ENV-$svc --force-new-deployment >/dev/null
done
```

(Real setup: do build/push/deploy from CI — GitHub Actions or CodePipeline — on merge.)

## 4. Run migrations (one-off task after images are live)

```bash
aws ecs run-task --cluster lp-consolidator-$ENV \
  --launch-type FARGATE --task-definition lp-consolidator-$ENV-api \
  --network-configuration "awsvpcConfiguration={subnets=[<private-subnet-ids>],securityGroups=[<ecs-sg>],assignPublicIp=DISABLED}" \
  --overrides '{"containerOverrides":[{"name":"api","command":["php","artisan","migrate","--force","--seed"]}]}'
```

## 5. Point Shopify at the env

- Add the app's **redirect URL**: `https://<app_domain>/api/shopify/callback`
- Set the **webhook address** base to `https://<webhook_domain>` (the app auto-registers order webhooks on connect)
- qa uses `qa-consolidator` / `qa-webhooks`; prod uses `consolidator` / `webhooks`

## Notes / decisions

- **APP_KEY** is generated once per env in Secrets Manager and injected into every
  task, so encrypted Shopify tokens decrypt across api/queue/scheduler.
- **Queue** uses SQS (`QUEUE_CONNECTION=sqs`) via the task IAM role (no static keys).
- **Cost lever:** one NAT gateway per env. For prod HA, switch to one NAT per AZ.
- The **SPA is served from an ECS `web` container** behind the ALB (mirrors local).
  Swapping to S3 + CloudFront later is a drop-in optimization.
- Destroy: `terraform destroy` per env (prod RDS has deletion protection + a final snapshot).
