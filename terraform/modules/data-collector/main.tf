# Zip the collector code

data "archive_file" "collector_zip" {
  type        = "zip"
  source_file = "${path.root}/../src/lambdas/data_collector.py"
  output_path = "${path.root}/.terraform/collector.zip"
}

# IAM Role for Collector Lambda
resource "aws_iam_role" "collector_role" {
  name = "${var.project_name}-collector-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# IAM Policy for DynamoDB PutItem
resource "aws_iam_policy" "collector_dynamodb_policy" {
  name = "${var.project_name}-collector-dynamodb"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["dynamodb:PutItem"]
      Effect   = "Allow"
      Resource = var.dynamodb_table_arn
    }]
  })
}

# Attach policies to Role
resource "aws_iam_role_policy_attachment" "collector_dynamodb_attach" {
  role       = aws_iam_role.collector_role.name
  policy_arn = aws_iam_policy.collector_dynamodb_policy.arn
}

resource "aws_iam_role_policy_attachment" "collector_basic_exec" {
  role       = aws_iam_role.collector_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Data Collector Lambda Function
resource "aws_lambda_function" "collector" {
  filename         = data.archive_file.collector_zip.output_path
  function_name    = "${var.project_name}-data-collector"
  role             = aws_iam_role.collector_role.arn
  handler          = "data_collector.lambda_handler"
  runtime          = "python3.14" 
  memory_size      = 128
  timeout          = 300 
  source_code_hash = data.archive_file.collector_zip.output_base64sha256
  
  # Layer provided by user
  layers = [var.pandas_layer_arn] 

  environment {
    variables = {
      URLS = var.collector_urls
    }
  }
}

# EventBridge rule (08:00 CET = 07:00 UTC)
resource "aws_cloudwatch_event_rule" "daily_collector" {
  name                = "${var.project_name}-daily-collector"
  description         = "Triggers the data collector Lambda daily at 8:00 CET"
  schedule_expression = "cron(0 7 * * ? *)" 
}

# Link EventBridge to Lambda
resource "aws_cloudwatch_event_target" "run_collector" {
  rule      = aws_cloudwatch_event_rule.daily_collector.name
  target_id = "collector_lambda"
  arn       = aws_lambda_function.collector.arn
}

# Grant EventBridge permission to invoke Lambda
resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.collector.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_collector.arn
}