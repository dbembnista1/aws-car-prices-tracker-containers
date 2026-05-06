variable "project_name" {
  type = string
}

variable "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table for IAM policy"
  type        = string
}

variable "cognito_user_pool_arn" {
  description = "ARN of the Cognito User Pool for the Authorizer"
  type        = string
}