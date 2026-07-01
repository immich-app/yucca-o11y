variable "env" {}
variable "stage" {}

# Netbird setup key from the netbird/cluster module (terragrunt dependency). Fed to
# every node's netbird ExtensionServiceConfig (NB_SETUP_KEY). Takes effect once the
# node runs a schematic that includes siderolabs/netbird.
variable "netbird_setup_key" {
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
  default = "v1.13.5"
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

# Talos disk-selector match (CEL) for the worker spare-disk UserVolumes.
# local-hostpath and local-hostpath-2 both use model + !system_disk, so Talos
# spreads them across the non-system disks — no per-node pinning, and it survives
# a re-provision. OVH's BYOI install picks the system disk non-deterministically
# (it varies per node), so anything position- or serial-specific would have to be
# maintained by hand; !system_disk sidesteps that. The install disk isn't pinned
# at all (see workers.tf) — Talos keeps whatever disk OVH installed onto.
variable "worker_data_disk_match" {
  type = string
}

# Second spare-disk UserVolume (local-hostpath-2); "" on envs with one spare.
variable "worker_data_disk2_match" {
  type    = string
  default = ""
}

# Per-node worker NIC names (public = DHCP, private = vRack static). OVH ships
# heterogeneous NICs even within one plan code, so these are pinned per-node.
variable "worker_nics" {
  type = map(object({
    public  = string
    private = string
  }))
}

# True only during initial bring-up of a brand-new env, before the Netbird
# extension has registered any node. Drop back to false once each node is on
# the netbird mesh, so future applies go via the vRack and the ingress firewall
# can drop public-NIC traffic without locking terraform out.
variable "use_public_endpoints" {
  type    = bool
  default = false
}
