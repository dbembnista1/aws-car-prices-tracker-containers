output "user_pool_id" {
  value = aws_cognito_user_pool.pool.id
}

output "client_id" {
  value = aws_cognito_user_pool_client.client.id
}

output "cognito_domain" {
  value = "${aws_cognito_user_pool_domain.main.domain}.auth.eu-central-1.amazoncognito.com"
}

output "user_pool_arn" {
  value = aws_cognito_user_pool.pool.arn
}