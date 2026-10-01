resource "local_file" "handler_in_package" {
  content  = file("${path.module}/../../../src/lambdas/data_collector_external.py")
  filename = "${path.module}/python_deps/data_collector_external.py"
}

data "archive_file" "collector_zip" {
  type        = "zip"
  source_dir  = "${path.module}/python_deps"
  output_path = "${path.root}/.terraform/external-collector.zip"
  excludes    = ["bin", "__pycache__"]
  depends_on  = [local_file.handler_in_package]
}

resource "aws_dynamodb_table" "external" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "date"

  attribute {
    name = "date"
    type = "S"
  }

  table_class                 = "STANDARD"
  deletion_protection_enabled = true
}

resource "aws_s3_bucket" "targets" {
  bucket_prefix = "${var.project_name}-collector-targets-"
}

resource "aws_s3_bucket_public_access_block" "targets" {
  bucket = aws_s3_bucket.targets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "targets" {
  bucket = aws_s3_bucket.targets.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "targets" {
  bucket = aws_s3_bucket.targets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "targets" {
  bucket = aws_s3_bucket.targets.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_iam_role" "collector_role" {
  name = "${var.project_name}-external-collector-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_policy" "collector_policy" {
  name = "${var.project_name}-external-collector"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "PutExternalPrices"
        Action   = ["dynamodb:PutItem"]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.external.arn
      },
      {
        Sid      = "ReadTargetsCatalog"
        Action   = ["s3:GetObject"]
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.targets.arn}/${var.targets_object_key}"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "collector_policy_attach" {
  role       = aws_iam_role.collector_role.name
  policy_arn = aws_iam_policy.collector_policy.arn
}

resource "aws_iam_role_policy_attachment" "collector_basic_exec" {
  role       = aws_iam_role.collector_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "collector" {
  filename         = data.archive_file.collector_zip.output_path
  function_name    = "${var.project_name}-external-collector"
  role             = aws_iam_role.collector_role.arn
  handler          = "data_collector_external.lambda_handler"
  runtime          = "python3.14"
  memory_size      = 512
  timeout          = 900
  source_code_hash = data.archive_file.collector_zip.output_base64sha256
  layers           = [var.pandas_layer_arn]

  environment {
    variables = {
      TABLE_NAME     = aws_dynamodb_table.external.name
      TARGETS_BUCKET = aws_s3_bucket.targets.bucket
      TARGETS_KEY    = var.targets_object_key
    }
  }

  depends_on = [aws_s3_bucket_public_access_block.targets]
}

resource "aws_cloudwatch_event_rule" "weekly_collector" {
  name                = "${var.project_name}-external-collector"
  description         = "Triggers the external collector Lambda once a week"
  schedule_expression = var.schedule_expression
}

resource "aws_cloudwatch_event_target" "run_collector" {
  rule      = aws_cloudwatch_event_rule.weekly_collector.name
  target_id = "external_collector_lambda"
  arn       = aws_lambda_function.collector.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.collector.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.weekly_collector.arn
}
