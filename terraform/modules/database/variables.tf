variable "table_name" {
  description = "Name of the DynamoDB table"
  type        = string
  default     = "car_prices"
}

variable "csv_file_path" {
  description = "Local path to the CSV file used to seed the DynamoDB table"
  type        = string
}

variable "tags" {
  description = "Tags to be applied to the database resources"
  type        = map(string)
  default     = {}
}