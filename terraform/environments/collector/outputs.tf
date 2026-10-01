output "lambda_name" {
  description = "External collector Lambda name"
  value       = module.external_collector.lambda_name
}

output "table_name" {
  description = "DynamoDB table car_prices_external (empty until the Lambda runs)"
  value       = module.external_collector.table_name
}

output "targets_bucket_name" {
  description = "Private bucket for the targets catalog. Upload: aws s3 cp collector_targets.json s3://BUCKET/KEY --profile collector"
  value       = module.external_collector.targets_bucket_name
}

output "targets_object_key" {
  description = "Object key the Lambda reads"
  value       = module.external_collector.targets_object_key
}
