output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.app.domain_name
}

output "cluster_name" {
  description = "Name of the ECS cluster (used by GitHub Actions)"
  value       = aws_ecs_cluster.main.name
}

output "service_name" {
  description = "Name of the ECS service (used by GitHub Actions)"
  value       = aws_ecs_service.app.name
}

output "alb_sg_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb_sg.id
}

output "ecs_sg_id" {
  description = "ID of the ECS tasks security group"
  value       = aws_security_group.ecs_sg.id
}
