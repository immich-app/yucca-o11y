data "ovh_cloud_project_loadbalancer_flavors" "envoy" {
  service_name = ovh_cloud_project.this.project_id
  region_name  = var.loadbalancer_region
}

locals {
  loadbalancer_flavor_id = one([
    for f in data.ovh_cloud_project_loadbalancer_flavors.envoy.flavors : f.id
    if f.name == var.loadbalancer_flavor
  ])
  # The LB lives in one Public Cloud region but reaches all workers over the
  # vRack L2. Pick the control-plane node whose region matches to index the
  # per-region private subnet.
  loadbalancer_subnet_key = one([
    for k, v in var.controlplane_nodes : k if v.region == var.loadbalancer_region
  ])
}

# Octavia LB on the vRack subnet, fronting Envoy. It holds the public IP (an
# inline-created floating IP via an inline-created gateway) and forwards over the
# vRack to Envoy's NodePort. L4 TCP passthrough — TLS still terminates at Envoy.
# This replaces MetalLB: the LB owns the public IP and talks to workers privately,
# so workers never source public-IP replies out the public NIC (the asymmetry that
# made MetalLB + an Additional IP unworkable here).
resource "ovh_cloud_project_loadbalancer" "envoy" {
  service_name = ovh_cloud_project.this.project_id
  region_name  = var.loadbalancer_region
  flavor_id    = local.loadbalancer_flavor_id
  name         = "o11y-${var.env}-envoy"

  network = {
    private = {
      network = {
        id        = ovh_cloud_project_network_private.cluster.regions_openstack_ids[var.loadbalancer_region]
        subnet_id = ovh_cloud_project_network_private_subnet_v2.cluster[local.loadbalancer_subnet_key].id
      }
      gateway_create     = { model = "s", name = "o11y-${var.env}-lb" }
      floating_ip_create = { description = "o11y-${var.env}-envoy" }
    }
  }

  listeners = [
    {
      port     = 443
      protocol = "tcp"
      pool = {
        algorithm = "roundRobin"
        protocol  = "tcp"
        health_monitor = {
          monitor_type     = "tcp"
          delay            = 10
          timeout          = 5
          max_retries      = 3
          max_retries_down = 3
        }
        members = [
          for k, w in var.worker_nodes : {
            name          = "o11y-${var.env}-worker-${k}"
            address       = w.private_ip
            protocol_port = var.envoy_node_port
          }
        ]
      }
    }
  ]
}
