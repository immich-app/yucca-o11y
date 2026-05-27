locals {
  cluster_name     = "o11y-${var.env}"
  controlplane_vip = cidrhost(var.private_network_cidr, var.controlplane_vip_offset)
  cluster_endpoint = "https://${local.controlplane_vip}:6443"

  controlplane_keys = sort(keys(var.controlplane_nodes))
  worker_keys       = sort(keys(var.worker_nodes))

  bootstrap_node_key = local.controlplane_keys[0]
  bootstrap_node     = var.controlplane_nodes[local.bootstrap_node_key]

  controlplane_endpoint_ips = {
    for k, v in var.controlplane_nodes :
    k => var.use_public_endpoints ? v.public_ip : v.private_ip
  }
  worker_endpoint_ips = {
    for k, v in var.worker_nodes :
    k => var.use_public_endpoints ? v.public_ip : v.private_ip
  }
  bootstrap_node_endpoint_ip = var.use_public_endpoints ? local.bootstrap_node.public_ip : local.bootstrap_node.private_ip

  # Operator-facing endpoint, surfaced for downstream modules' providers. Cross-DC
  # ARP for the floating VIP is unreliable from outside the vRack, so we point
  # operators at a static CP IP (all three are in the apiserver cert SANs).
  operator_endpoint = "https://${local.bootstrap_node.private_ip}:6443"
}

resource "talos_machine_secrets" "this" {}

data "talos_client_configuration" "this" {
  cluster_name         = local.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes = concat(
    [for k in local.controlplane_keys : local.controlplane_endpoint_ips[k]],
    [for k in local.worker_keys : local.worker_endpoint_ips[k]],
  )
  endpoints = [for k in local.controlplane_keys : local.controlplane_endpoint_ips[k]]
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.controlplane]

  node                 = local.bootstrap_node_endpoint_ip
  client_configuration = talos_machine_secrets.this.client_configuration

  timeouts = {
    create = "10m"
  }
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_machine_bootstrap.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.bootstrap_node_endpoint_ip
}
