output "lambda_name" {
  description = "The name of the Data Collector Lambda function"
  value       = aws_lambda_function.collector.function_name
}

output "collector_role_name" {
  description = "The name of the IAM role used by the collector Lambda"
  value       = aws_iam_role.collector_role.name
}