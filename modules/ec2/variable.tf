
variable "subnet_id" {
  type = string
}

variable "sg_id" {
  type = string
}

variable "ami_id" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "key_name" {
  type = string
}

variable "user_data" {
  description = "Cloud-init script executed when the instance is first created."
  type        = string
  default     = null
}
