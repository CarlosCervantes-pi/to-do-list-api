output "ec2_public_ip" {
  value = aws_instance.web.public_ip
}

output "api_url" {
  value = "http://${aws_instance.web.public_ip}:8000"
}

output "rds_endpoint" {
  value = aws_db_instance.postgres.endpoint
}
