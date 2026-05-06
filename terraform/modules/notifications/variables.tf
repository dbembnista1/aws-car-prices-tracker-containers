variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "subscriber_email" {
  description = "Email address to send notifications to"
  type        = string
}

variable "collector_lambda_name" {
  description = "Name of the Lambda function to attach the destination to"
  type        = string
}

variable "collector_role_name" {
  description = "Name of the Lambda IAM role to attach SNS publish permissions to"
  type        = string
}