variable "env" {}
variable "stage" {}

variable "tailscale_api_key" {
  sensitive = true
}
variable "tailscale_tailnet_id" {
  sensitive = true
}

variable "controlplane_nodes" {
  type = map(object({
    name       = string
    region     = string
    public_ip  = string
    private_ip = string
  }))
}

variable "worker_nodes" {
  type = map(object({
    name       = string
    datacenter = string
    public_ip  = string
    private_ip = string
  }))
}

variable "private_network_cidr" {
  type = string
}

# Talos ships per-platform installers; sharing one breaks upgrade on the other.
variable "talos_installer_images" {
  type = object({
    bare_metal   = string
    public_cloud = string
  })
}

variable "talos_version" {
  type    = string
  default = "v1.13.0"
}

variable "controlplane_vip_offset" {
  type    = number
  default = 5
}

variable "controlplane_disk" {
  type    = string
  default = "/dev/vda"
}

variable "worker_disk" {
  type    = string
  default = "/dev/nvme0n1"
}

# True only during initial bring-up of a brand-new env, before the Tailscale
# extension has registered any node. Drop back to false once each node is on
# the tailnet, so future applies go via the vRack and the ingress firewall
# can drop public-NIC traffic without locking terraform out.
variable "use_public_endpoints" {
  type    = bool
  default = false
}
