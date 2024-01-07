# Copyright 2024 ke.liu#foxmail.com

variable "ipsec_subnet_id" {
  description   = "the subnet id of HA-IPSec EC2"
  type          = string
}

variable "ipsec_instance_type" {
  description   = "the instance type of that host, we prefre high CPU freq instances"
  type          = string
  default       = "c6i.large"
}

variable "ipsec_key_name" {
  description   = "the SSH key name for that host"
  type          = string
}

variable "ipsec_init_script" {
  description   = "from whichi ip, we will SSH this host"
  type          = string
  default       = "init.sh"
}

variable "ipsec_china_region" {
  description   = "is it china regins? default to yes"
  type          = bool
  default       = true
}