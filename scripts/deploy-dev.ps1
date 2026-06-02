$ErrorActionPreference = 'Stop'

$AwsProfile = "dev"
$Environment = "dev"

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

if (-not (Test-Path $BackendConf)) {
  Write-Host "backend.conf not found. Reading values from bootstrap outputs..."

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

  Write-Host "backend.conf generated from bootstrap outputs."
}

Set-Location $EnvDir

$env:TZ = "UTC"

terraform init -backend-config="backend.conf"

terraform apply -auto-approve
if ($LASTEXITCODE -ne 0) {
  Write-Error "ERROR: terraform apply failed. Aborting."
  exit 1
}

$Branch = git -C "$ScriptDir\.." rev-parse --abbrev-ref HEAD

gh workflow run deploy-app.yml --ref $Branch -f environment=$Environment

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
