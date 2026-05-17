#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/../terraform"

if [ ! -f "backend.conf" ]; then
  echo "ERROR: terraform/backend.conf not found. Copy backend.conf.example and fill in your values."
  exit 1
fi

terraform init -backend-config="backend.conf"

terraform apply -auto-approve

BRANCH=$(git -C "$SCRIPT_DIR/.." rev-parse --abbrev-ref HEAD)

gh workflow run deploy-app.yml --ref "$BRANCH"

sleep 5

RUN_ID=""
RETRY_COUNT=0
while [ -z "$RUN_ID" ] && [ $RETRY_COUNT -lt 6 ]; do
    RUN_ID=$(gh run list --workflow=deploy-app.yml --branch "$BRANCH" --limit 1 --json databaseId --jq '.[0].databaseId')
    if [ -z "$RUN_ID" ] || [ "$RUN_ID" == "null" ]; then
        echo "Waiting for the workflow run to appear..."
        RUN_ID=""
        sleep 5
        ((RETRY_COUNT++))
    fi
done

if [ -z "$RUN_ID" ]; then
    echo "ERROR: Could not find the workflow run after waiting."
    exit 1
fi

gh run watch "$RUN_ID"

APP_URL=$(terraform output -raw cloudfront_domain_name)
echo ""
echo "App available at: https://$APP_URL"
