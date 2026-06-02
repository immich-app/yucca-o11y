# Native (untagged) vRack VLAN, so vlan_id = 0. Env isolation comes from separate
# vRacks, not VLAN tags.
resource "ovh_cloud_project_network_private" "cluster" {
  service_name = ovh_cloud_project.this.project_id
  name         = "o11y-${var.env}"
  vlan_id      = 0
  regions      = [for n in var.controlplane_nodes : n.region]

  depends_on = [ovh_vrack_cloudproject.this]
}

resource "ovh_cloud_project_network_private_subnet_v2" "cluster" {
  for_each = var.controlplane_nodes

  service_name = ovh_cloud_project.this.project_id
  # Per-region OpenStack UUID; the composite `.id` isn't accepted here.
  network_id = ovh_cloud_project_network_private.cluster.regions_openstack_ids[each.value.region]
  region     = each.value.region
  name       = "o11y-${var.env}-${each.key}"
  cidr       = var.private_network_cidr
  dhcp       = true

  # No subnet gateway IP: with it set, OVH makes the private gateway the instance
  # default route, which strands the CP's egress off its public NIC.
  enable_gateway_ip               = false
  use_default_public_dns_resolver = false
  dns_nameservers                 = ["1.1.1.1", "9.9.9.9"]
}
