variable "env" {}

variable "netbox_url" {
  type = string
}

variable "netbox_token" {
  type      = string
  sensitive = true
}

# Ranges allocated elsewhere (ovh + netbird modules), consumed via terragrunt dependencies.
variable "private_network_cidr" {
  type = string
}

variable "netbird_service_cidr" {
  type = string
}

variable "netbird_egress_cidr" {
  type = string
}
