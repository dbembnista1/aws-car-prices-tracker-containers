terraform {
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

variable "github_token" {
  description = "GitHub token for managing repository resources"
  type        = string
  default     = null
  sensitive   = true
}

provider "github" {
  owner = var.github_owner
  token = var.github_token
}
