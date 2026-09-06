variable "domain_name" {
  description = "Root domain name, e.g. rezedev.site"
  type        = string
}

variable "instance_public_ip" {
  description = "Public IP of the EC2 instance the domain should resolve to"
  type        = string
}
