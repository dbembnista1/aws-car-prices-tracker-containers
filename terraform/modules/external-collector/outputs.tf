output "lambda_name" {
  description = "External collector Lambda function name"
  value       = aws_lambda_function.collector.function_name
}

output "table_name" {
  description = "DynamoDB table written by the external collector"
  value       = aws_dynamodb_table.external.name
}

output "table_arn" {
  description = "ARN of the external collector DynamoDB table"
  value       = aws_dynamodb_table.external.arn
}

output "targets_bucket_name" {
  description = "Private S3 bucket for collector_targets.json"
  value       = aws_s3_bucket.targets.bucket
}

output "targets_object_key" {
  description = "Object key the Lambda reads from the targets bucket"
  value       = var.targets_object_key
}
