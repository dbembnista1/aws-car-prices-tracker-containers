param(
  [string]$AwsProfile = "dev",
  [string]$Environment = "dev",
  [int]$LoadWorkers = 20,
  [int]$LoadDurationSeconds = 300,
  [switch]$RunLoadTest,
  [switch]$WatchOnly
)

$ErrorActionPreference = 'Stop'

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

Push-Location $EnvDir
try {
  $ClusterName = terraform output -raw ecs_cluster_name
  $ServiceName = terraform output -raw ecs_service_name
  $AlbDnsName  = terraform output -raw alb_dns_name
} catch {
  Write-Error "ERROR: Could not read Terraform outputs. Run 'terraform apply' in $EnvDir first."
  exit 1
} finally {
  Pop-Location
}

$AlbUrl = "http://$AlbDnsName/"

function Get-EcsServiceStatus {
  aws ecs describe-services --cluster $ClusterName --services $ServiceName --profile $AwsProfile `
    --query "services[0].{desired:desiredCount,running:runningCount,pending:pendingCount}" --output json |
    ConvertFrom-Json
}

function Show-TaskCount {
  param([string]$Label = "now")

  $Status = Get-EcsServiceStatus
  Write-Host ""
  Write-Host "=== Task count ($Label) ==="
  Write-Host "  desired : $($Status.desired)"
  Write-Host "  running : $($Status.running)"
  Write-Host "  pending : $($Status.pending)"
  Write-Host "==========================="
}

function Show-TaskDetails {
  $TaskArns = aws ecs list-tasks --cluster $ClusterName --service-name $ServiceName --profile $AwsProfile `
    --query "taskArns" --output json | ConvertFrom-Json

  if (-not $TaskArns -or $TaskArns.Count -eq 0) {
    Write-Host "  (no tasks listed)"
    return
  }

  aws ecs describe-tasks --cluster $ClusterName --tasks $TaskArns --profile $AwsProfile `
    --query "tasks[].{task:taskArn,az:availabilityZone,lastStatus:lastStatus,health:healthStatus}" --output table
}

Write-Host ""
Write-Host "ECS cluster : $ClusterName"
Write-Host "ECS service : $ServiceName"
Write-Host "ALB URL     : $AlbUrl (load test target - not CloudFront)"

Show-TaskCount -Label "baseline"
Write-Host ""
Write-Host "Tasks by AZ:"
Show-TaskDetails
Write-Host ""

Write-Host "Scalable targets:"
aws application-autoscaling describe-scalable-targets --service-namespace ecs --profile $AwsProfile `
  --query "ScalableTargets[?contains(ResourceId, '$ServiceName')]" --output table

Write-Host "Scaling policies:"
aws application-autoscaling describe-scaling-policies --service-namespace ecs --profile $AwsProfile `
  --query "ScalingPolicies[?contains(ResourceId, '$ServiceName')].[PolicyName,PolicyType]" --output table

if ($WatchOnly) {
  Write-Host ""
  Write-Host "Watch mode - Ctrl+C to stop."
  while ($true) {
    Start-Sleep -Seconds 30
    Show-TaskCount -Label (Get-Date -Format "HH:mm:ss")
  }
}

if (-not $RunLoadTest) {
  Write-Host ""
  Write-Host "Next steps:"
  Write-Host "  Scale-out test : .\scripts\test-ecs-autoscaling.ps1 -RunLoadTest"
  Write-Host "  Watch counts   : .\scripts\test-ecs-autoscaling.ps1 -WatchOnly"
  Write-Host ""
  Write-Host "After load test, wait 10-15 min for scale-in back to min_capacity."
  exit 0
}

Write-Host ""
Write-Host "Starting load test for ${LoadDurationSeconds}s with $LoadWorkers parallel workers..."
Write-Host "Press Ctrl+C to stop early and begin scale-in observation."

$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$Jobs = 1..$LoadWorkers | ForEach-Object {
  Start-Job -ScriptBlock {
    param($Url, $DurationSeconds)
    $Deadline = (Get-Date).AddSeconds($DurationSeconds)
    while ((Get-Date) -lt $Deadline) {
      try {
        Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 10 | Out-Null
      } catch {
        # Ignore transient errors during load generation
      }
    }
  } -ArgumentList $AlbUrl, $LoadDurationSeconds
}

while ($Stopwatch.Elapsed.TotalSeconds -lt $LoadDurationSeconds) {
  Start-Sleep -Seconds 30
  $ElapsedLabel = "{0}s" -f [int]$Stopwatch.Elapsed.TotalSeconds
  Show-TaskCount -Label $ElapsedLabel
}

$Jobs | Stop-Job -PassThru | Remove-Job

Write-Host ""
Write-Host "Load test finished. Recent scaling activities:"
aws application-autoscaling describe-scaling-activities --service-namespace ecs --profile $AwsProfile `
  --max-results 5 --output table

Show-TaskCount -Label "post-load"
Write-Host ""
Write-Host "Run with -WatchOnly to observe scale-in over the next 10-15 minutes."
