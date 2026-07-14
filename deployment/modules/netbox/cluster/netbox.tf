# Per-env IPAM registration for the ranges the ovh + netbird modules allocate — the
# values arrive via terragrunt dependencies, so the NetBox record can't drift from code.
resource "netbox_prefix" "vrack" {
  prefix      = var.private_network_cidr
  status      = "active"
  description = "o11y ${var.env} vRack (Talos nodes; advertised to the mesh)"
}

resource "netbox_prefix" "netbird_service" {
  prefix      = var.netbird_service_cidr
  status      = "active"
  description = "o11y ${var.env} k8s secondary ServiceCIDR (mesh-gateway VIP)"
}

resource "netbox_prefix" "netbird_egress" {
  prefix      = var.netbird_egress_cidr
  status      = "active"
  description = "o11y ${var.env} pod egress range (Multus netbird-egress NAD)"
}
