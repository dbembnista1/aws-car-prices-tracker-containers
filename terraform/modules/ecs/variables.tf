variable "project_name" {
  description = "Name of the project, used as a prefix for resource names"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where resources will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of public subnet IDs for ALB and Fargate tasks (min. 2 AZs)"
  type        = list(string)
}

variable "ecr_repository_url" {
  description = "Full URL of the ECR repository (without tag)"
  type        = string
}

variable "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table the container needs read access to"
  type        = string
}

variable "cognito_domain" {
  description = "Cognito hosted UI domain passed as env var to the container"
  type        = string
}

variable "cognito_client_id" {
  description = "Cognito app client ID passed as env var to the container"
  type        = string
}

variable "api_base_url" {
  description = "API Gateway base URL passed as env var to the container"
  type        = string
}

variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

variable "container_port" {
  description = "Port the Express app listens on inside the container"
  type        = number
  default     = 3000
}

variable "cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate task memory in MiB"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of running Fargate tasks"
  type        = number
  default     = 1
}

variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default     = {}
}
