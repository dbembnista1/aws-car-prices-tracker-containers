# packages for lambdas
data "archive_file" "find_models_zip" {
  type        = "zip"
  source_file = "${path.root}/../src/lambdas/api_find_models.py"
  output_path = "${path.root}/.terraform/find_models.zip"
}

data "archive_file" "get_prices_zip" {
  type        = "zip"
  source_file = "${path.root}/../src/lambdas/api_get_prices_by_model.py"
  output_path = "${path.root}/.terraform/get_prices.zip"

}
# IAM for lambdas

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name        = "${var.project_name}-lambda-dynamodb"
  description = "Allows Lambda to read DynamoDB"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["dynamodb:Scan", "dynamodb:Query", "dynamodb:GetItem"]
      Effect   = "Allow"
      Resource = var.dynamodb_table_arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda_basic_exec" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# create lambdas

resource "aws_lambda_function" "find_models" {
  filename         = data.archive_file.find_models_zip.output_path
  function_name    = "${var.project_name}-find-models"
  role             = aws_iam_role.lambda_role.arn
  handler          = "api_find_models.lambda_handler"
  runtime          = "python3.14"
  source_code_hash = data.archive_file.find_models_zip.output_base64sha256
}

resource "aws_lambda_function" "get_prices" {
  filename         = data.archive_file.get_prices_zip.output_path
  function_name    = "${var.project_name}-get-prices"
  role             = aws_iam_role.lambda_role.arn
  handler          = "api_get_prices_by_model.lambda_handler"
  runtime          = "python3.14"
  source_code_hash = data.archive_file.get_prices_zip.output_base64sha256
}

# api gw and cognito

resource "aws_api_gateway_rest_api" "api" {
  name = "${var.project_name}-api"
}

resource "aws_api_gateway_authorizer" "cognito" {
  name          = "CognitoAuthorizer"
  type          = "COGNITO_USER_POOLS"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  provider_arns = [var.cognito_user_pool_arn]
}

# /models
resource "aws_api_gateway_resource" "models" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "models"
}

resource "aws_api_gateway_method" "models_get" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.models.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "models_get_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.models.id
  http_method             = aws_api_gateway_method.models_get.http_method
  integration_http_method = "POST" # Lambda zawsze wymaga POST od strony API GW
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.find_models.invoke_arn
}

# /car
resource "aws_api_gateway_resource" "car" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "car"
}

resource "aws_api_gateway_method" "car_get" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.car.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "car_get_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.car.id
  http_method             = aws_api_gateway_method.car_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_prices.invoke_arn
}


# allow gw to invoke lambdas

resource "aws_lambda_permission" "apigw_invoke_models" {
  statement_id  = "AllowAPIGatewayInvokeModels"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.find_models.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_invoke_car" {
  statement_id  = "AllowAPIGatewayInvokeCar"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_prices.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}


# CORS (Cross-Origin Resource Sharing)
# ==========================================
# CORS (Cross-Origin Resource Sharing)
# ==========================================

#  models endpoint
resource "aws_api_gateway_method" "models_options" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.models.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "models_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.models.id
  http_method = aws_api_gateway_method.models_options.http_method
  type        = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "models_options_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.models.id
  http_method = aws_api_gateway_method.models_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "models_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.models.id
  http_method = aws_api_gateway_method.models_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_integration.models_options_integration]
}

# car endpoint
resource "aws_api_gateway_method" "car_options" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.car.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "car_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.car.id
  http_method = aws_api_gateway_method.car_options.http_method
  type        = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "car_options_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.car.id
  http_method = aws_api_gateway_method.car_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "car_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.car.id
  http_method = aws_api_gateway_method.car_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_integration.car_options_integration]
}

# Deploy api gw

# Deploy api gw
resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [
    aws_api_gateway_integration.models_get_integration,
    aws_api_gateway_integration.car_get_integration,
    aws_api_gateway_integration.models_options_integration,
    aws_api_gateway_integration.car_options_integration
  ]
  rest_api_id = aws_api_gateway_rest_api.api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_integration.models_get_integration.id,
      aws_api_gateway_integration.car_get_integration.id,
      aws_api_gateway_integration.models_options_integration.id,
      aws_api_gateway_integration.car_options_integration.id,
      aws_api_gateway_integration_response.models_options_integration_response.id,
      aws_api_gateway_integration_response.car_options_integration_response.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "prod"
}