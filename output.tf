output "instance_public_ip" {
  value = module.ec2.public_ip
}

output "linkding_url" {
  description = "HTTPS URL for Linkding"
  value       = "https://rezedev.site"
}

output "route53_name_servers" {
  description = "Set these 4 as the nameservers at Hostinger"
  value       = module.dns.name_servers
}

output "domain_url" {
  value = "https://rezedev.site"
}
