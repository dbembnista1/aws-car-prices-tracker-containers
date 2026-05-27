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

variable "enable_github_secrets" {
  description = "Set to true to automatically configure CICD for infra (OICD connection to AWS needed) using GitHub Actions Secrets"
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

variable "github_token" {
  description = "GitHub token for managing repository resources"
  type        = string
  default     = null
  sensitive   = true
}
