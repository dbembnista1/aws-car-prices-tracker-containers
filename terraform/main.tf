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

#Apache server
module "compute" {
  source             = "./modules/compute"
  project_name       = var.project_name
  instance_type      = "t3.micro"
  tags               = var.common_tags
  
  #network
  vpc_id             = module.network.vpc_id 
  subnet_id          = module.network.public_subnet_id 
  
  #db
  dynamodb_table_arn = module.database.table_arn
  
  #variables for html file
  api_base_url            = module.api.api_url
  cognito_domain          = module.cognito.cognito_domain
  cognito_client_id       = module.cognito.client_id
}


module "cognito" {
  source        = "./modules/cognito"
  project_name  = var.project_name
  web_server_ip = module.compute.instance_public_ip
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
  count  = var.enable_data_collector ? 1 : 0
  
  project_name       = var.project_name
  dynamodb_table_arn = module.database.table_arn
  collector_urls     = var.collector_urls
  pandas_layer_arn   = var.pandas_layer_arn
}



#GITHUB secrets (CICD enablement for web server, optional)


resource "github_actions_secret" "ec2_host" {
  # If enable_github_secrets = true, create 1. Else 0.
  count           = var.enable_github_secrets ? 1 : 0
  
  repository      = var.github_repository
  secret_name     = "EC2_HOST"
  plaintext_value = module.compute.instance_public_ip
}


resource "github_actions_secret" "ec2_ssh_key" {
  count           = var.enable_github_secrets ? 1 : 0
  
  repository      = var.github_repository
  secret_name     = "EC2_SSH_KEY"
  plaintext_value = module.compute.private_key_pem
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

# Notifications module (SNS + Lambda Formatter)
module "notifications" {
  source = "./modules/notifications"
  
  # Only creates if collector is enabled AND email is not empty
  count = (var.enable_data_collector && var.subscriber_email != "") ? 1 : 0

  project_name          = var.project_name
  subscriber_email      = var.subscriber_email
  
  # Dependencies from the data_collector module
  collector_lambda_name = module.data_collector[0].lambda_name
  collector_role_name   = module.data_collector[0].collector_role_name
}