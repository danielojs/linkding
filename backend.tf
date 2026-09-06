terraform {
  backend "s3" {
    bucket       = "kami-dev-tfstate"
    key          = "dev/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
  }
}
