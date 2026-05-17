
output "server_public_ip" {
  value = module.compute.instance_public_ip
}

output "api_base_url" {
  value = module.api.api_url
}

output "cloudfront_domain_name" {
  value = module.ecs.cloudfront_domain_name
}