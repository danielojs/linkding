resource "aws_route53_zone" "this" {
  name = var.domain_name
}

resource "aws_route53_record" "apex_a" {
  zone_id = aws_route53_zone.this.zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = 300
  records = [var.instance_public_ip]
}
