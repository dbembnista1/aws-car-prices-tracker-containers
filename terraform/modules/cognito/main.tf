# User pool
resource "aws_cognito_user_pool" "pool" {
  name = "${var.project_name}-users"

  username_configuration {
    case_sensitive = false
  }

  alias_attributes         = ["preferred_username"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  schema {
    attribute_data_type = "String"
    name                = "email"
    required            = true
    mutable             = true
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
}


resource "random_string" "domain_suffix" {
  length  = 6
  special = false
  upper   = false
}

# unique dmain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.project_name}-users-${random_string.domain_suffix.result}" 
  user_pool_id = aws_cognito_user_pool.pool.id
}

# App client
resource "aws_cognito_user_pool_client" "client" {
  name         = "${var.project_name}-client"
  user_pool_id = aws_cognito_user_pool.pool.id

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]

  supported_identity_providers = ["COGNITO"]

  
  callback_urls = ["https://${var.web_server_ip}/api-form-with-authentication-hostedUI.html"]
  logout_urls   = ["https://${var.web_server_ip}/api-form-with-authentication-hostedUI.html"]

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["implicit"]
  allowed_oauth_scopes                 = ["email", "openid", "phone", "profile"]
  
  prevent_user_existence_errors = "ENABLED"
}