variable "netbird_tf_pat" {
  sensitive = true
}

variable "env" {}

# Matches the env's private_network_cidr from the ovh module — the vRack subnet
# the Talos nodes advertise as a NetBird network route for operator access.
variable "private_network_cidr" {
  type = string
}
