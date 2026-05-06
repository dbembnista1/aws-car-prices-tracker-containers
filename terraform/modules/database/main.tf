# Temporary S3 bucket for the CSV seed file
resource "aws_s3_bucket" "temp_bucket" {
  bucket_prefix = "car-prices-temp-bucket-"
  force_destroy = true

  tags = var.tags
}

# Upload the CSV file from local disk to S3
resource "aws_s3_object" "seed_file" {
  bucket = aws_s3_bucket.temp_bucket.id
  key    = "historical_data.csv"
  source = var.csv_file_path
  etag   = filemd5(var.csv_file_path)
}

# DynamoDB table created directly from the S3 CSV file
resource "aws_dynamodb_table" "car_prices" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "date"

  attribute {
    name = "date"
    type = "S"
  }

  table_class                 = "STANDARD"
  deletion_protection_enabled = false

  import_table {
    input_format = "CSV"

    s3_bucket_source {
      bucket     = aws_s3_bucket.temp_bucket.id
      key_prefix = aws_s3_object.seed_file.key
    }

    input_format_options {
      csv {
        delimiter = ","
      }
    }
  }

  tags = var.tags
}