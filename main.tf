module "vpc" {
  source      = "./modules/vpc"
  vpc_cidr    = "10.0.0.0/16"
  subnet_cidr = "10.0.1.0/24"
  public      = true
  cidr_block  = "0.0.0.0/0"
}

module "security_group" {
  source           = "./modules/security-group"
  vpc_id           = module.vpc.vpc_id
  allow_ssh        = true
  allow_http       = true
  allow_https      = true
  allow_all_egress = true
}

module "ec2" {
  source        = "./modules/ec2"
  ami_id        = "ami-0532913178263be11"
  key_name      = "universal-key"
  instance_type = "t3.micro"
  sg_id         = module.security_group.sg_id
  subnet_id     = module.vpc.subnet_id
  user_data     = file("${path.module}/scripts/linkding-bootstrap.sh")

  depends_on = [module.vpc, module.security_group]
}

module "dns" {
  source             = "./modules/dns"
  domain_name        = "rezedev.site"
  instance_public_ip = module.ec2.public_ip

  depends_on = [module.ec2]
}
