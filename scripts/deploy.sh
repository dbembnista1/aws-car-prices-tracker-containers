#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_CONF="$SCRIPT_DIR/../terraform/backend.conf"

if [ ! -f "$BACKEND_CONF" ]; then
  echo "backend.conf not found. Reading values from bootstrap outputs..."

  pushd "$SCRIPT_DIR/../terraform/bootstrap" > /dev/null
  BUCKET_NAME=$(terraform output -raw state_bucket_name)
  TABLE_NAME=$(terraform output -raw dynamodb_table_name)
  REGION=$(terraform output -raw aws_region)
  popd > /dev/null

  if [ -z "$BUCKET_NAME" ] || [ -z "$TABLE_NAME" ]; then
    echo "ERROR: Could not read bootstrap outputs. Run 'terraform apply' in terraform/bootstrap first."
    exit 1
  fi

  cat > "$BACKEND_CONF" <<EOF
bucket         = "$BUCKET_NAME"
key            = "terraform.tfstate"
region         = "$REGION"
dynamodb_table = "$TABLE_NAME"
encrypt        = true
EOF

  echo "backend.conf generated from bootstrap outputs."
fi

cd "$SCRIPT_DIR/../terraform"

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
