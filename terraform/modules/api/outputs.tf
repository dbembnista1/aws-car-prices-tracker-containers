output "api_url" {
  description = "The base URL of the deployed API Gateway"
  value       = aws_api_gateway_stage.prod.invoke_url
}