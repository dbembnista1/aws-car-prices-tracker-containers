variable "repository_name" {
  description = "Name of the ECR repository"
  type        = STRING
}

variable "tags" {
  description = "Tags to apply to the repository"
  type        = map(STRING)
  default     = {}
}
