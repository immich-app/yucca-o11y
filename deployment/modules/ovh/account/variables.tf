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

# Control-plane (Public Cloud / KVM) schematic: tailscale + qemu-guest-agent.
variable "talos_schematic_id" {
  type    = string
  default = "7d4c31cbd96db9f90c874990697c523482b2bae27fb4631d5583dcd9c281b1ff"
}

# Worker (bare-metal) schematic: tailscale only. qemu-guest-agent must NOT be
# present on bare metal — it blocks on a virtio port that never appears, which
# wedges the Talos boot sequence and reboots the node in a loop.
variable "talos_worker_schematic_id" {
  type    = string
  default = "4a0d65c669d46663f377e7161e50cfd570c401f26fd9e7bda34a0216b6f1922b"
}

# Image must be pre-uploaded out-of-band (talos:dl:cp + talos:ul:cp mise tasks) —
# the OVH provider doesn't upload custom images.
variable "talos_public_cloud_image_name" {
  type    = string
  default = "talos-1.13.0-tailscale-qemu"
}

# IPLB tier and geographic zone (public-IP location). The LB reaches the workers
# cross-DC over the vRack regardless of zone.
variable "loadbalancer_plan_code" {
  type    = string
  default = "iplb-lb1"
}

variable "loadbalancer_zone" {
  type    = string
  default = "gra"
}

# A small unused range in the cluster subnet for the IPLB's vRack NAT IPs.
variable "loadbalancer_nat_cidr" {
  type    = string
  default = "10.150.200.192/27"
}

# NodePort the Envoy data-plane Service is pinned to; the LB members target it.
# Must match the nodePort in kubernetes/apps/base/envoy-proxy.
variable "envoy_node_port" {
  type    = number
  default = 30443
}
