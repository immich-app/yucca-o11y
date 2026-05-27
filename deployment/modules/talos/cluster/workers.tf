resource "tailscale_tailnet_key" "worker" {
  for_each = var.worker_nodes

  reusable            = true
  ephemeral           = true
  preauthorized       = true
  recreate_if_invalid = "always"
  expiry              = 7776000
  description         = "Talos key ${each.value.name}"
  tags = [
    "tag:project-yucca",
    "tag:env-${var.env}",
  ]
}

data "talos_machine_configuration" "worker" {
  cluster_name     = local.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
}

resource "talos_machine_configuration_apply" "worker" {
  for_each = var.worker_nodes

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = local.worker_endpoint_ips[each.key]

  on_destroy = {
    reboot   = true
    reset    = true
    graceful = false
  }

  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk  = var.worker_disk
          image = var.talos_installer_images.bare_metal
        }
        network = {
          # NIC names match the Broadcom NetXtreme-E predictable scheme on the
          # SYS-2 hardware currently in stock. If a re-provision lands on a
          # different chipset, switch to deviceSelector.physicalAddress (MAC).
          interfaces = [
            {
              interface = "eno1np0"
              dhcp      = true
            },
            {
              interface = "eno2np1"
              addresses = ["${each.value.private_ip}/${split("/", var.private_network_cidr)[1]}"]
            }
          ]
        }
      }
    }),
    <<-EOT
      apiVersion: v1alpha1
      kind: HostnameConfig
      auto: "off"
      hostname: ${each.value.name}
    EOT
    ,
    # Tailscale extension is baked into the worker image's schematic; without
    # this config block the service starts unauthenticated and hangs.
    <<-EOT
      name: tailscale
      apiVersion: v1alpha1
      kind: ExtensionServiceConfig
      environment:
      - TS_AUTHKEY=${tailscale_tailnet_key.worker[each.key].key}
      - TS_HOSTNAME=${each.value.name}
      - TS_EXTRA_ARGS=--accept-dns=false
    EOT
    ,
    <<-EOT
      apiVersion: v1alpha1
      kind: VolumeConfig
      name: EPHEMERAL
      provisioning:
        diskSelector:
          match: system_disk
        minSize: 256GB
        maxSize: 256GB
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
    # Disk model match (not just `!system_disk`) so a future re-provision on
    # different hardware fails loudly instead of silently picking another disk.
    <<-EOT
      apiVersion: v1alpha1
      kind: UserVolumeConfig
      name: local-hostpath
      provisioning:
        diskSelector:
          match: disk.model == "WDC CL SN720 SDAQNTW-512G-2000" && !system_disk
        minSize: 100GB
        grow: true
    EOT
    ,
    <<-EOT
      apiVersion: v1alpha1
      kind: NetworkDefaultActionConfig
      ingress: block
    EOT
    ,
    <<-EOT
      apiVersion: v1alpha1
      kind: NetworkRuleConfig
      name: apid
      portSelector:
        ports:
          - 50000
        protocol: tcp
      ingress:
        - subnet: 100.64.0.0/10
        - subnet: fd7a:115c:a1e0::/48
        - subnet: ${var.private_network_cidr}
    EOT
    ,
    <<-EOT
      apiVersion: v1alpha1
      kind: NetworkRuleConfig
      name: kubelet
      portSelector:
        ports:
          - 10250
        protocol: tcp
      ingress:
        - subnet: ${var.private_network_cidr}
    EOT
    ,
    # Flannel VXLAN overlay (kube-flannel runs with backend port 4789). Pinned to
    # the vRack via the cluster CNI config, so the only trusted source is the
    # private CIDR.
    <<-EOT
      apiVersion: v1alpha1
      kind: NetworkRuleConfig
      name: flannel-vxlan
      portSelector:
        ports:
          - 4789
        protocol: udp
      ingress:
        - subnet: ${var.private_network_cidr}
    EOT
  ]
}
