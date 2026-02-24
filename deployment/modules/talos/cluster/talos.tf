resource "talos_machine_secrets" "nodes" {
  for_each = var.nodes
}

data "talos_machine_configuration" "nodes" {
  for_each         = var.nodes
  cluster_name     = "o11y-${var.env}-${each.key}"
  machine_type     = "controlplane"
  cluster_endpoint = "https://o11y-${var.env}-${each.key}:6443"
  machine_secrets  = talos_machine_secrets.nodes[each.key].machine_secrets
}

data "talos_client_configuration" "nodes" {
  for_each             = var.nodes
  cluster_name         = "o11y-${var.env}-${each.key}"
  client_configuration = talos_machine_secrets.nodes[each.key].client_configuration
  nodes                = [var.node_ips[each.key]]
}

resource "talos_machine_configuration_apply" "nodes" {
  for_each                    = var.nodes
  client_configuration        = talos_machine_secrets.nodes[each.key].client_configuration
  machine_configuration_input = data.talos_machine_configuration.nodes[each.key].machine_configuration
  node                        = var.node_ips[each.key]
  on_destroy = {
    reboot   = true
    reset    = true
    graceful = false
  }
  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk = "/dev/nvme0n1"
        }
      }
      cluster = {
        allowSchedulingOnControlPlanes = true
      }
    }),
    <<-EOT
      apiVersion: v1alpha1
      kind: HostnameConfig
      hostname: o11y-${var.env}-${each.key}
      auto: off
    EOT
  ,
    <<-EOT
      name: tailscale
      apiVersion: v1alpha1
      kind: ExtensionServiceConfig
      environment:
      - TS_AUTHKEY=${tailscale_tailnet_key.nodes[each.key].key}
    EOT
  ,
    <<-EOT
      apiVersion: v1alpha1
      kind: VolumeConfig
      name: EPHEMERAL
      provisioning:
        diskSelector:
          match: system_disk
        minSize: 50GB
        maxSize: 50GB
        grow: false
    EOT
  ,
    <<-EOT
      apiVersion: v1alpha1
      kind: UserVolumeConfig
      name: hostpath
      provisioning:
        diskSelector:
          match: system_disk
        minSize: 20GB
        grow: true
    EOT
  ,
    <<-EOT
      apiVersion: v1alpha1
      kind: LinkConfig
      name: eno1
      up: true
    EOT
  ,
    <<-EOT
      apiVersion: v1alpha1
      kind: DHCPv4Config
      name: eno1
    EOT
  ,
    <<-EOT
      apiVersion: v1alpha1
      kind: LinkConfig
      name: eno2
      up: true
    EOT
  ,
    <<-EOT
      apiVersion: v1alpha1
      kind: VLANConfig
      name: eno2.2600
      vlanID: 2600
      vlanMode: 802.1q
      parent: eno2
      up: true
      addresses:
        - address: ${each.value.vlan_ip}/16
    EOT
  ]
}

resource "talos_machine_bootstrap" "nodes" {
  for_each             = var.nodes
  node                 = talos_machine_configuration_apply.nodes[each.key].node
  client_configuration = talos_machine_secrets.nodes[each.key].client_configuration
  timeouts = {
    create = "1m"
  }
}

resource "talos_cluster_kubeconfig" "nodes" {
  for_each             = var.nodes
  client_configuration = talos_machine_secrets.nodes[each.key].client_configuration
  node                 = var.node_ips[each.key]
}
