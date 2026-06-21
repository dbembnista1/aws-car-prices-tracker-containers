
output "api_base_url" {
  value = module.api.api_url
}

output "cloudfront_domain_name" {
  value = module.ecs.cloudfront_domain_name
}

output "ecs_cluster_name" {
  description = "ECS cluster name (for autoscaling verification)"
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "ECS service name (for autoscaling verification)"
  value       = module.ecs.service_name
}

output "alb_dns_name" {
  description = "ALB DNS name (use for load tests — bypass CloudFront)"
  value       = module.ecs.alb_dns_name
}
