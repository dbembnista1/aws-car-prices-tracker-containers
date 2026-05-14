variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "app_hostname" {
  description = "Hostname (ALB DNS name) used for Cognito callback and logout URLs"
  type        = string
}