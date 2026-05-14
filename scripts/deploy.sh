#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/../terraform"

terraform init \
  -backend-config="bucket=car-prices-terraform-state-eubfxr" \
  -backend-config="key=terraform.tfstate" \
  -backend-config="region=eu-central-1" \
  -backend-config="dynamodb_table=car-prices-terraform-locks" \
  -backend-config="encrypt=true"

terraform apply -auto-approve

BRANCH=$(git -C "$SCRIPT_DIR/.." rev-parse --abbrev-ref HEAD)

gh workflow run "App CI/CD (Docker to ECR)" --ref "$BRANCH"

sleep 5
RUN_ID=$(gh run list --workflow=deploy-app.yml --branch "$BRANCH" --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN_ID"

ALB=$(terraform output -raw alb_dns_name)
echo ""
echo "App available at: https://$ALB"
echo "(self-signed cert — przeglądarka może pokazać ostrzeżenie, kliknij 'Advanced' -> 'Proceed')"
