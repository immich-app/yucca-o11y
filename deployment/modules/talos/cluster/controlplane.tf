resource "tailscale_tailnet_key" "controlplane" {
  for_each = var.controlplane_nodes

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

data "tailscale_device" "controlplane" {
  for_each = var.controlplane_nodes

  hostname = each.value.name
  wait_for = "300s"

  depends_on = [talos_machine_bootstrap.this]
}

data "talos_machine_configuration" "controlplane" {
  cluster_name     = local.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
}

resource "talos_machine_configuration_apply" "controlplane" {
  for_each = var.controlplane_nodes

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = local.controlplane_endpoint_ips[each.key]

  on_destroy = {
    reboot   = true
    reset    = true
    graceful = false
  }

  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk  = var.controlplane_disk
          image = var.talos_installer_images.public_cloud
        }
        network = {
          interfaces = [
            {
              # eth1's IP arrives via OpenStack metadata; the VIP layers on top.
              interface = "eth1"
              vip = {
                ip = local.controlplane_vip
              }
            }
          ]
        }
      }
      cluster = {
        allowSchedulingOnControlPlanes = false
        # kube-proxy (nftables mode) defaults --nodeport-addresses to the node's
        # primary IP — here the private vRack IP — so NodePorts only answered on
        # the private NIC and the OVH IPLB (which hits the workers' PUBLIC IP)
        # got dead probes. Open NodePorts on every interface so the public NIC
        # serves 30443 too. Generated into the kube-proxy DaemonSet by Talos.
        proxy = {
          extraArgs = {
            "nodeport-addresses" = "0.0.0.0/0"
          }
        }
        network = {
          # Flannel defaults its VXLAN endpoint to the default-route NIC (public),
          # which sends east-west pod traffic over the internet and is dropped by
          # the ingress firewall. Pin the VTEP to the vRack interface so VXLAN runs
          # on the private network the firewall trusts.
          cni = {
            name = "flannel"
            flannel = {
              extraArgs = ["--iface-can-reach=${cidrhost(var.private_network_cidr, 1)}"]
            }
          }
        }
        apiServer = {
          # VIP for in-cluster traffic; CP private IPs for operators reaching the
          # apiserver over Tailscale (the floating VIP doesn't ARP reliably across DCs).
          certSANs = concat(
            [local.controlplane_vip],
            [for k in local.controlplane_keys : var.controlplane_nodes[k].private_ip],
          )
        }
      }
    }),
    # `auto: "off"` must be quoted — YAML 1.1 parses bare `off` as the boolean
    # false, but the AutoHostnameKind enum needs the literal string.
    <<-EOT
      apiVersion: v1alpha1
      kind: HostnameConfig
      auto: "off"
      hostname: ${each.value.name}
    EOT
    ,
    <<-EOT
      name: tailscale
      apiVersion: v1alpha1
      kind: ExtensionServiceConfig
      environment:
      - TS_AUTHKEY=${tailscale_tailnet_key.controlplane[each.key].key}
      - TS_HOSTNAME=${each.value.name}
      - TS_ROUTES=${var.private_network_cidr}
      - TS_EXTRA_ARGS=--accept-dns=false
    EOT
    ,
    # Talos ingress firewall — default-deny on host-bound services. Allow
    # rules use Tailscale CGNAT (operators) and the vRack CIDR (intra-cluster).
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
      name: trustd
      portSelector:
        ports:
          - 50001
        protocol: tcp
      ingress:
        - subnet: ${var.private_network_cidr}
    EOT
    ,
    <<-EOT
      apiVersion: v1alpha1
      kind: NetworkRuleConfig
      name: kube-apiserver
      portSelector:
        ports:
          - 6443
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
      name: etcd
      portSelector:
        ports:
          - 2379-2380
        protocol: tcp
      ingress:
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
    # the vRack via --iface-can-reach above, so the only trusted source is the
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
