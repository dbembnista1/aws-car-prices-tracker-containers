# 1. SNS Topic for raw data from Data Collector
resource "aws_sns_topic" "raw_prices" {
  name = "${var.project_name}-raw-prices-topic"
}

# 2. SNS Topic for formatted email notifications
resource "aws_sns_topic" "formatted_notifications" {
  name = "${var.project_name}-notifications-topic"
}

# 3. Email subscription to the formatted topic
resource "aws_sns_topic_subscription" "email_target" {
  topic_arn = aws_sns_topic.formatted_notifications.arn
  protocol  = "email"
  endpoint  = var.subscriber_email
}

# 4. Lambda Destinations: Connect Data Collector to raw SNS topic
resource "aws_lambda_function_event_invoke_config" "collector_destination" {
  function_name = var.collector_lambda_name

  destination_config {
    on_success {
      destination = aws_sns_topic.raw_prices.arn
    }
  }
}

# 5. IAM Policy: Allow Data Collector to publish to raw SNS topic
resource "aws_iam_role_policy" "collector_sns_publish" {
  name = "${var.project_name}-collector-sns-publish"
  role = var.collector_role_name 

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = "sns:Publish"
      Effect   = "Allow"
      Resource = aws_sns_topic.raw_prices.arn
    }]
  })
}

# =========================================================
# FORMATTING LAMBDA
# =========================================================

# Package Formatting Lambda code
data "archive_file" "formatter_zip" {
  type        = "zip"
  source_file = "${path.root}/../src/lambdas/email_formatting.py"
  output_path = "${path.root}/.terraform/formatter.zip"
}

# IAM Role for Formatting Lambda
resource "aws_iam_role" "formatter_role" {
  name = "${var.project_name}-formatter-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# IAM Policy for Formatting Lambda to publish to the formatted SNS topic
resource "aws_iam_role_policy" "formatter_policy" {
  name = "${var.project_name}-formatter-policy"
  role = aws_iam_role.formatter_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "sns:Publish"
        Effect   = "Allow"
        Resource = aws_sns_topic.formatted_notifications.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "formatter_basic_exec" {
  role       = aws_iam_role.formatter_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Formatting Lambda Function
resource "aws_lambda_function" "formatter" {
  filename         = data.archive_file.formatter_zip.output_path
  function_name    = "${var.project_name}-formatter"
  role             = aws_iam_role.formatter_role.arn
  handler          = "email_formatting.lambda_handler"
  runtime          = "python3.14"
  source_code_hash = data.archive_file.formatter_zip.output_base64sha256

  environment {
    variables = {
      OUTPUT_SNS_TOPIC_ARN = aws_sns_topic.formatted_notifications.arn
    }
  }
}

# SNS Trigger: Raw SNS topic invokes Formatting Lambda
resource "aws_sns_topic_subscription" "trigger_formatter" {
  topic_arn = aws_sns_topic.raw_prices.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.formatter.arn
}

# Lambda Permission: Allow raw SNS topic to invoke Formatting Lambda
resource "aws_lambda_permission" "allow_sns_invoke" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.formatter.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.raw_prices.arn
}