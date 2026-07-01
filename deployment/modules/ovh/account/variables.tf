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
  default = "v1.13.5"
}

# Control-plane (Public Cloud / KVM) schematic: qemu-guest-agent + netbird.
variable "talos_schematic_id" {
  type    = string
  default = "bbfcb7053b1609712a977830952455432825890922cb6bac23cea34b980970f1"
}

# Worker (bare-metal) schematic: netbird only. qemu-guest-agent must NOT be
# present on bare metal — it blocks on a virtio port that never appears, which
# wedges the Talos boot sequence and reboots the node in a loop.
variable "talos_worker_schematic_id" {
  type    = string
  default = "7326f0cbca7a0e700ac1efa3f32e88df9ebe5010e6e842a8ed36fdc99ee98ead"
}

# Image must be pre-uploaded out-of-band (talos:dl:cp + talos:ul:cp mise tasks) —
# the OVH provider doesn't upload custom images.
variable "talos_public_cloud_image_name" {
  type    = string
  default = "talos-1.13.5-qemu-netbird"
}

# IPLB tier and geographic zone (public-IP location). The LB reaches the workers
# cross-DC over the vRack regardless of zone.
variable "loadbalancer_plan_code" {
  type    = string
  default = "iplb-lb1"
}

# IPLB zones (anycast — same public IP announced from each). One zone for
# staging; several for production ingress HA (e.g. ["gra", "rbx", "sbg"]). Each
# extra zone is a billable addon (~£16/mo at lb1). NOTE: this set is fixed at LB
# order time (plan_option is ForceNew + ignored after create); changing it on a
# live LB means recreating it (new IP) or ordering the zone addon out-of-band.
variable "loadbalancer_zones" {
  type    = list(string)
  default = ["gra"]
}

# NodePort the Envoy data-plane Service is pinned to; the LB members target it.
# Must match the nodePort in kubernetes/apps/base/envoy-proxy.
variable "envoy_node_port" {
  type    = number
  default = 30443
}
