#!/bin/bash
set -e

AWS_PROFILE_NAME="collector"
ENVIRONMENT="collector"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_DIR="$SCRIPT_DIR/../terraform/environments/$ENVIRONMENT"

export AWS_PROFILE="$AWS_PROFILE_NAME"

echo "Verifying AWS identity for profile '$AWS_PROFILE_NAME'..."
if ! IDENTITY=$(aws sts get-caller-identity --profile "$AWS_PROFILE_NAME" --output text 2>/dev/null); then
  echo "ERROR: Could not verify AWS identity for profile '$AWS_PROFILE_NAME'. Run 'aws configure --profile $AWS_PROFILE_NAME' first."
  exit 1
fi
echo "Authenticated: $IDENTITY"

cd "$ENV_DIR"

terraform init -reconfigure

terraform apply -auto-approve

BUCKET=$(terraform output -raw targets_bucket_name)
KEY=$(terraform output -raw targets_object_key)
TABLE=$(terraform output -raw table_name)

echo ""
echo "Collector stack applied (local state)."
echo "Table: $TABLE (empty until the Lambda runs)."
echo "Upload the gitignored catalog, then invoke or wait for EventBridge:"
echo "  aws s3 cp collector_targets.json s3://$BUCKET/$KEY --profile $AWS_PROFILE_NAME"
