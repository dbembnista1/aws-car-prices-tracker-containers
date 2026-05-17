$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location "$ScriptDir\..\terraform"

if (-not (Test-Path "backend.conf")) {
  Write-Error "ERROR: terraform/backend.conf not found. Copy backend.conf.example and fill in your values."
  exit 1
}

$env:TZ = "UTC"

terraform init -backend-config="backend.conf"

terraform apply -auto-approve
if ($LASTEXITCODE -ne 0) {
  Write-Error "ERROR: terraform apply failed. Aborting."
  exit 1
}

$Branch = git -C "$ScriptDir\.." rev-parse --abbrev-ref HEAD

gh workflow run deploy-app.yml --ref $Branch

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
