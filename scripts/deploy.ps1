$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location "$ScriptDir\..\terraform"

terraform init `
  -backend-config="bucket=car-prices-terraform-state-eubfxr" `
  -backend-config="key=terraform.tfstate" `
  -backend-config="region=eu-central-1" `
  -backend-config="dynamodb_table=car-prices-terraform-locks" `
  -backend-config="encrypt=true"

terraform apply -auto-approve

$Branch = git -C "$ScriptDir\.." rev-parse --abbrev-ref HEAD

gh workflow run "App CI/CD (Docker to ECR)" --ref $Branch

Start-Sleep -Seconds 5
$RunId = gh run list --workflow=deploy-app.yml --branch $Branch --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch $RunId

$Alb = terraform output -raw alb_dns_name
Write-Host ""
Write-Host "App available at: https://$Alb"
Write-Host "(self-signed cert — przeglądarka może pokazać ostrzeżenie, kliknij 'Advanced' -> 'Proceed')"
