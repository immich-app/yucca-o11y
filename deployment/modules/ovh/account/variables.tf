variable "stage" {}
variable "env" {}

variable "ovh_application_key" {
  sensitive = true
}
variable "ovh_application_secret" {
  sensitive = true
}
variable "ovh_consumer_key" {
  sensitive = true
}

variable "controlplane_nodes" {
  type = map(object({
    region      = string
    flavor_name = string
    private_ip  = string
  }))
}

variable "worker_nodes" {
  type = map(object({
    datacenter              = string
    plan_code               = string
    storage_option          = string
    ram_option              = string
    bandwidth_option        = string
    public_bandwidth_option = string
    private_ip              = string
  }))
}

variable "private_network_cidr" {
  type = string
}

variable "vrack_name" {
  type    = string
  default = "o11y"
}

variable "talos_version" {
  type    = string
  default = "v1.13.0"
}

variable "talos_schematic_id" {
  type    = string
  default = "7d4c31cbd96db9f90c874990697c523482b2bae27fb4631d5583dcd9c281b1ff"
}

# Image must be pre-uploaded out-of-band (talos:dl + talos:ul mise tasks) —
# the OVH provider doesn't upload custom images.
variable "talos_public_cloud_image_name" {
  type    = string
  default = "talos-1.13.0-tailscale-qemu"
}

variable "additional_ip_plan_code" {
  type    = string
  default = "ip-v4-s30-ripe"
}
