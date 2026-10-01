$ErrorActionPreference = 'Stop'

$AwsProfile = "collector"
$Environment = "collector"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$EnvDir = "$ScriptDir\..\terraform\environments\$Environment"

$env:AWS_PROFILE = $AwsProfile

Write-Host "Verifying AWS identity for profile '$AwsProfile'..."
$Identity = aws sts get-caller-identity --profile $AwsProfile --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $Identity.Account) {
  Write-Error "ERROR: Could not verify AWS identity for profile '$AwsProfile'. Run 'aws configure --profile $AwsProfile' first."
  exit 1
}
Write-Host "Authenticated as $($Identity.Arn) (account $($Identity.Account))."

Set-Location $EnvDir

$env:TZ = "UTC"

terraform init -reconfigure

terraform apply -auto-approve
if ($LASTEXITCODE -ne 0) {
  Write-Error "ERROR: terraform apply failed. Aborting."
  exit 1
}

$Bucket = terraform output -raw targets_bucket_name
$Key = terraform output -raw targets_object_key
$Table = terraform output -raw table_name

Write-Host ""
Write-Host "Collector stack applied (local state)."
Write-Host "Table: $Table (empty until the Lambda runs)."
Write-Host "Upload the gitignored catalog, then invoke or wait for EventBridge:"
Write-Host "  aws s3 cp collector_targets.json s3://$Bucket/$Key --profile $AwsProfile"
