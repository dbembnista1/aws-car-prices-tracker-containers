
output "server_public_ip" {
  value = module.compute.instance_public_ip
}

output "api_base_url" {
  value = module.api.api_url
}