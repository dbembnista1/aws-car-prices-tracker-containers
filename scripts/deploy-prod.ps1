$ErrorActionPreference = 'Stop'

$AwsProfile = "prod"
$Environment = "prod"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$EnvDir = "$ScriptDir\..\terraform\environments\$Environment"
$BootstrapDir = "$EnvDir\bootstrap"
$BackendConf = "$EnvDir\backend.conf"

$env:AWS_PROFILE = $AwsProfile

Write-Host "Verifying AWS identity for profile '$AwsProfile'..."
$Identity = aws sts get-caller-identity --profile $AwsProfile --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $Identity.Account) {
  Write-Error "ERROR: Could not verify AWS identity for profile '$AwsProfile'. Run 'aws configure --profile $AwsProfile' first."
  exit 1
}
Write-Host "Authenticated as $($Identity.Arn) (account $($Identity.Account))."

Write-Host "Syncing backend.conf from bootstrap outputs..."

Push-Location $BootstrapDir
try {
  $Outputs = terraform output -json | ConvertFrom-Json
} finally {
  Pop-Location
}

$BucketName = $Outputs.state_bucket_name.value
$TableName  = $Outputs.dynamodb_table_name.value
$Region     = $Outputs.aws_region.value

if (-not $BucketName -or -not $TableName) {
  Write-Error "ERROR: Could not read bootstrap outputs. Run 'terraform apply' in $BootstrapDir first."
  exit 1
}

@"
bucket         = "$BucketName"
key            = "terraform.tfstate"
region         = "$Region"
dynamodb_table = "$TableName"
encrypt        = true
"@ | Set-Content $BackendConf

Write-Host "backend.conf synced (bucket: $BucketName)."

Set-Location $EnvDir

$env:TZ = "UTC"

terraform init -reconfigure -backend-config="backend.conf"

terraform apply -auto-approve
if ($LASTEXITCODE -ne 0) {
  Write-Error "ERROR: terraform apply failed. Aborting."
  exit 1
}

$Branch = git -C "$ScriptDir\.." rev-parse --abbrev-ref HEAD
$RepoRoot = "$ScriptDir\.."

$RemoteBranch = git -C $RepoRoot ls-remote --heads origin $Branch 2>$null
if ([string]::IsNullOrWhiteSpace($RemoteBranch)) {
  Write-Error @"
ERROR: Branch '$Branch' is not on GitHub (origin).
GitHub Actions workflow_dispatch requires the ref to exist on the remote.

  git push -u origin $Branch
  ./scripts/deploy-prod.ps1

Or trigger only the app deploy after push:
  gh workflow run deploy-app.yml --ref $Branch -f environment=$Environment
"@
  exit 1
}

Write-Host "Triggering deploy-app workflow on branch '$Branch'..."
gh workflow run deploy-app.yml --ref $Branch -f environment=$Environment
if ($LASTEXITCODE -ne 0) {
  Write-Error "ERROR: Could not trigger deploy-app workflow. See message above."
  exit 1
}

Start-Sleep -Seconds 5

$RunId = ""
$RetryCount = 0
while ([string]::IsNullOrWhiteSpace($RunId) -and $RetryCount -lt 6) {
    $RunId = gh run list --workflow=deploy-app.yml --branch $Branch --limit 1 --json databaseId --jq '.[0].databaseId'
    if ([string]::IsNullOrWhiteSpace($RunId)) {
        Write-Host "Waiting for the workflow run to appear..."
        Start-Sleep -Seconds 5
        $RetryCount++
    }
}

if ([string]::IsNullOrWhiteSpace($RunId)) {
    Write-Error "ERROR: Could not find the workflow run after waiting."
    exit 1
}

gh run watch $RunId

$AppUrl = terraform output -raw cloudfront_domain_name
Write-Host ""
Write-Host "App available at: https://$AppUrl"
