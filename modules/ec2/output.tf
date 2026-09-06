output "instance_id" {
  value = aws_instance.this.id
}

output "public_ip" {
  description = "Elastic IP address associated with the instance"
  value       = aws_eip.this.public_ip
}
