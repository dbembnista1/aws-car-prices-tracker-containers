module "external_collector" {
  source = "../../modules/external-collector"

  project_name        = var.project_name
  table_name          = "car_prices_external"
  targets_object_key  = var.targets_object_key
  schedule_expression = var.schedule_expression
  pandas_layer_arn    = var.pandas_layer_arn
}
