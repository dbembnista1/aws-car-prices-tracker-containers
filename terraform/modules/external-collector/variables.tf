variable "project_name" {
  description = "Project name used for resource naming (no environment suffix)"
  type        = string
}

variable "table_name" {
  description = "DynamoDB table for external series (empty at apply, no seed)"
  type        = string
}

variable "targets_object_key" {
  description = "S3 object key of the private targets catalog. Object is uploaded out of band (aws s3 cp), not by Terraform."
  type        = string
}

variable "schedule_expression" {
  description = "EventBridge schedule for the external collector"
  type        = string
  default     = "cron(0 7 ? * SUN *)"
}

variable "pandas_layer_arn" {
  description = "ARN of the AWS SDK Pandas layer (provides requests, same as data-collector)"
  type        = string
}
