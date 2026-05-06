variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
}

# Bardzo ważne dla LinkedIn Showcase - nie hardkodujemy ARN w polityce!
variable "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table for IAM policy"
  type        = string
}

# Jeśli używasz własnego VPC, te zmienne też będą potrzebne:
variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "subnet_id" {
  description = "ID of the public subnet where EC2 will be deployed"
  type        = string
}

#variables for html file 

variable "api_base_url" {
  type        = string
  description = "The Invoke URL of the API Gateway stage. Used by the frontend to communicate with Lambda functions."
}

variable "cognito_domain" {
  type        = string
  description = "The full domain of the Cognito User Pool (e.g., your-domain.auth.eu-central-1.amazoncognito.com) for Hosted UI."
}

variable "cognito_client_id" {
  type        = string
  description = "The ID of the Cognito User Pool Client used for application authentication."
}

