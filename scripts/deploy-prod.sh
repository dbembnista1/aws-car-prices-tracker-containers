#!/bin/bash
set -e

AWS_PROFILE_NAME="prod"
ENVIRONMENT="prod"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_DIR="$SCRIPT_DIR/../terraform/environments/$ENVIRONMENT"
BOOTSTRAP_DIR="$ENV_DIR/bootstrap"
BACKEND_CONF="$ENV_DIR/backend.conf"

export AWS_PROFILE="$AWS_PROFILE_NAME"

echo "Verifying AWS identity for profile '$AWS_PROFILE_NAME'..."
if ! IDENTITY=$(aws sts get-caller-identity --profile "$AWS_PROFILE_NAME" --output text 2>/dev/null); then
  echo "ERROR: Could not verify AWS identity for profile '$AWS_PROFILE_NAME'. Run 'aws configure --profile $AWS_PROFILE_NAME' first."
  exit 1
fi
echo "Authenticated: $IDENTITY"

echo "Syncing backend.conf from bootstrap outputs..."

pushd "$BOOTSTRAP_DIR" > /dev/null
BUCKET_NAME=$(terraform output -raw state_bucket_name)
TABLE_NAME=$(terraform output -raw dynamodb_table_name)
REGION=$(terraform output -raw aws_region)
popd > /dev/null

if [ -z "$BUCKET_NAME" ] || [ -z "$TABLE_NAME" ]; then
  echo "ERROR: Could not read bootstrap outputs. Run 'terraform apply' in $BOOTSTRAP_DIR first."
  exit 1
fi

cat > "$BACKEND_CONF" <<EOF
bucket         = "$BUCKET_NAME"
key            = "terraform.tfstate"
region         = "$REGION"
dynamodb_table = "$TABLE_NAME"
encrypt        = true
EOF

echo "backend.conf synced (bucket: $BUCKET_NAME)."

cd "$ENV_DIR"

terraform init -reconfigure -backend-config="backend.conf"

terraform apply -auto-approve

BRANCH=$(git -C "$SCRIPT_DIR/.." rev-parse --abbrev-ref HEAD)

if ! git -C "$SCRIPT_DIR/.." ls-remote --exit-code --heads origin "$BRANCH" > /dev/null 2>&1; then
  echo "ERROR: Branch '$BRANCH' is not on GitHub (origin)."
  echo "GitHub Actions workflow_dispatch requires the ref to exist on the remote."
  echo ""
  echo "  git push -u origin $BRANCH"
  echo "  ./scripts/deploy-prod.sh"
  echo ""
  echo "Or trigger only the app deploy after push:"
  echo "  gh workflow run deploy-app.yml --ref $BRANCH -f environment=$ENVIRONMENT"
  exit 1
fi

echo "Triggering deploy-app workflow on branch '$BRANCH'..."
gh workflow run deploy-app.yml --ref "$BRANCH" -f environment="$ENVIRONMENT"

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
