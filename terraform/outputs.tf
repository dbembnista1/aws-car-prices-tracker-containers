
output "api_base_url" {
  value = module.api.api_url
}

output "cloudfront_domain_name" {
  value = module.ecs.cloudfront_domain_name
}