variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "car-prices"
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Project     = "CarPrices"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}
