variable "vpc_id" {
  type = string
}

variable "allow_ssh" {
  type    = bool
  default = false
}

variable "allow_http" {
  type    = bool
  default = false
}

variable "allow_all_egress" {
  type    = bool
  default = false
}

variable "allow_https" {
  type    = bool
  default = false
}
