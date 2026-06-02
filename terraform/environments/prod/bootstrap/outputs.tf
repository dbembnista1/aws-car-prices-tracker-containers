output "state_bucket_name" {
  value       = aws_s3_bucket.terraform_state.bucket
  description = "The name of the S3 bucket for Terraform state"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.terraform_locks.name
  description = "The name of the DynamoDB table for state locking"
}

output "aws_region" {
  value = var.aws_region
}

output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions_role.arn
  description = "ARN of the IAM Role used by GitHub Actions"
}

output "github_environment" {
  value       = local.github_environment
  description = "Name of the GitHub Environment scoping secrets/variables for this account"
}
