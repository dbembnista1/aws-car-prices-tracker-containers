variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table where collector will put data"
  type        = string
}

variable "collector_urls" {
  description = "Comma-separated list of URLs to collect data from"
  type        = string
}

variable "pandas_layer_arn" {
  description = "ARN of the AWS SDK Pandas Layer"
  type        = string
}