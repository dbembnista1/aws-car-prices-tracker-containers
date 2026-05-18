# Main entry point for car prices infrastructure
module "database" {
  source        = "./modules/database"
  table_name    = "car_prices"
  csv_file_path = "${path.module}/data/historical_data.csv"
  tags          = var.common_tags
}


module "network" {
  source       = "./modules/network"
  project_name = var.project_name
}

module "ecr" {
  source          = "./modules/ecr"
  repository_name = "${var.project_name}-app"
  tags            = var.common_tags
}

module "ecs" {
  source = "./modules/ecs"

  project_name       = var.project_name
  vpc_id             = module.network.vpc_id
  subnet_ids         = module.network.public_subnet_ids
  ecr_repository_url = module.ecr.repository_url
  dynamodb_table_arn = module.database.table_arn

  cognito_domain    = module.cognito.cognito_domain
  cognito_client_id = module.cognito.client_id
  api_base_url      = module.api.api_url

  tags = var.common_tags
}


module "cognito" {
  source       = "./modules/cognito"
  project_name = var.project_name
  app_hostname = module.ecs.cloudfront_domain_name
}



module "api" {
  source                = "./modules/api"
  project_name          = var.project_name
  dynamodb_table_arn    = module.database.table_arn
  cognito_user_pool_arn = module.cognito.user_pool_arn
}

# Data collecting feature (optional)

module "data_collector" {
  source = "./modules/data-collector"

  # If enable_data_collector = true, create 1. Else 0.
  count = var.enable_data_collector ? 1 : 0

  project_name       = var.project_name
  dynamodb_table_arn = module.database.table_arn
  collector_urls     = var.collector_urls
  pandas_layer_arn   = var.pandas_layer_arn
}



#GITHUB variables

resource "github_actions_variable" "project_name" {
  count         = var.enable_github_secrets ? 1 : 0
  repository    = var.github_repository
  variable_name = "PROJECT_NAME"
  value         = var.project_name
}

resource "github_actions_variable" "cognito_domain" {
  count         = var.enable_github_secrets ? 1 : 0
  repository    = var.github_repository
  variable_name = "COGNITO_DOMAIN"
  value         = module.cognito.cognito_domain
}

resource "github_actions_variable" "cognito_client_id" {
  count         = var.enable_github_secrets ? 1 : 0
  repository    = var.github_repository
  variable_name = "COGNITO_CLIENT_ID"
  value         = module.cognito.client_id
}

resource "github_actions_variable" "api_base_url" {
  count         = var.enable_github_secrets ? 1 : 0
  repository    = var.github_repository
  variable_name = "API_BASE_URL"
  value         = module.api.api_url
}

resource "github_actions_variable" "ecr_repository_url" {
  count         = var.enable_github_secrets ? 1 : 0
  repository    = var.github_repository
  variable_name = "ECR_REPOSITORY_URL"
  value         = module.ecr.repository_url
}

resource "github_actions_variable" "ecs_cluster_name" {
  count         = var.enable_github_secrets ? 1 : 0
  repository    = var.github_repository
  variable_name = "ECS_CLUSTER_NAME"
  value         = module.ecs.cluster_name
}

resource "github_actions_variable" "ecs_service_name" {
  count         = var.enable_github_secrets ? 1 : 0
  repository    = var.github_repository
  variable_name = "ECS_SERVICE_NAME"
  value         = module.ecs.service_name
}

# Notifications module (SNS + Lambda Formatter)
module "notifications" {
  source = "./modules/notifications"

  # Only creates if collector is enabled AND email is not empty
  count = (var.enable_data_collector && var.subscriber_email != "") ? 1 : 0

  project_name     = var.project_name
  subscriber_email = var.subscriber_email

  # Dependencies from the data_collector module
  collector_lambda_name = module.data_collector[0].lambda_name
  collector_role_name   = module.data_collector[0].collector_role_name
}
