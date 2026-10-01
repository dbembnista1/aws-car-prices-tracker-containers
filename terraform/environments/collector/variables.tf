variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "car-prices"
}

variable "common_tags" {
  description = "Common tags applied to all resources. Environment is hardcoded per environment (this file lives only in environments/collector)."
  type        = map(string)
  default = {
    Project     = "CarPrices"
    Environment = "collector"
    ManagedBy   = "Terraform"
  }
}

variable "targets_object_key" {
  description = "S3 key of the private targets catalog. Upload with aws s3 cp; not stored in Terraform."
  type        = string
  default     = "collector_targets.json"
}

variable "schedule_expression" {
  description = "EventBridge schedule for the external collector (weekly by default)"
  type        = string
  default     = "cron(0 7 ? * SUN *)"
}

variable "pandas_layer_arn" {
  description = "ARN of the AWS SDK Pandas Layer"
  type        = string
  default     = "arn:aws:lambda:eu-central-1:336392948345:layer:AWSSDKPandas-Python314:2"
}
