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
variable "enable_github_secrets" {
  description = "Set to true to automatically configure CICD for web server code (EC2 IP and SSH Key needed) and configure CICD for infra (OICD connection to AWS needed) using GitHub Actions Secrets"
  type        = bool
  default     = false
}

variable "github_repository" {
  description = "Name of the GitHub repository for secrets injection"
  type        = string
  default     = ""
}

variable "github_owner" {
  description = "GitHub username or organization owning the repository"
  type        = string
  default     = ""
}

variable "enable_data_collector" {
  description = "Set to true to deploy the daily data collector Lambda"
  type        = bool
  default     = false
}

variable "collector_urls" {
  description = "Comma-separated list of URLs to collect data from. Required if enable_data_collector is true."
  type        = string
  default     = ""
}

variable "pandas_layer_arn" {
  description = "ARN of the AWS SDK Pandas Layer"
  type        = string
  default     = "arn:aws:lambda:eu-central-1:336392948345:layer:AWSSDKPandas-Python314:2" 
}

variable "subscriber_email" {
  description = "Email address for notifications. If empty, notifications are disabled."
  type        = string
  default     = ""
}