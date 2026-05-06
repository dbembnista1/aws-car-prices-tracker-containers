output "instance_public_ip" {
  description = "Public IP address of the web server"
  value       = aws_eip.web_server_eip.public_ip
}

output "instance_public_dns" {
  description = "Public DNS of the web server"
  value       = aws_instance.web_server.public_dns
}


output "private_key_pem" {
  description = "Private SSH key for the EC2 instance"
  value       = tls_private_key.ec2_key.private_key_pem
  sensitive   = true 
}