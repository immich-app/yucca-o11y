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
        # Spegel (kube-system DaemonSet) serves images peer-to-peer, so containerd
        # must keep unpacked layers around to serve them. Talos merges *.part files
        # into its CRI config; applying this reboots the node (containerd restart).
        files = [
          {
            op      = "create"
            path    = "/etc/cri/conf.d/20-customization.part"
            content = <<-TOML
              [plugins."io.containerd.cri.v1.images"]
                discard_unpacked_layers = false
            TOML
          }
        ]
        # Pin the kubelet's node IP to the vRack subnet so the Kubernetes
        # InternalIP is always the private IP and never falls back to the
        # Tailscale CGNAT address (which happens if eth1 has no IP at kubelet
        # start — see the static address below).
        kubelet = {
          nodeIP = {
            validSubnets = [var.private_network_cidr]
          }
        }
        network = {
          interfaces = [
            {
              # Static private IP rather than DHCP. OVH's private-network DHCP
              # NAKs the renew after a subnet/port rebuild ("address not
              # available"), stranding the CP off the vRack on reboot even though
              # the port's fixed IP is correct. The address matches that fixed IP,
              # which port-security already permits. The VIP layers on top.
              interface = "eth1"
              addresses = ["${each.value.private_ip}/${split("/", var.private_network_cidr)[1]}"]
              vip = {
                ip = local.controlplane_vip
              }
            }
          ]
        }
      }
      cluster = {
        allowSchedulingOnControlPlanes = false
        # Control-plane components bind their metrics to localhost by default, so
        # VMAgent (on a worker) can't scrape them. Bind to all interfaces; the
        # Talos ingress firewall below keeps the ports private (vRack + pod CIDR
        # only) — the public NIC stays default-deny. controller-manager (:10257)
        # and scheduler (:10259) serve authenticated HTTPS; etcd (:2381) is
        # unauthenticated HTTP, so the firewall is its only protection.
        controllerManager = {
          extraArgs = {
            "bind-address" = "0.0.0.0"
          }
        }
        scheduler = {
          extraArgs = {
            "bind-address" = "0.0.0.0"
          }
        }
        etcd = {
          extraArgs = {
            "listen-metrics-urls" = "http://0.0.0.0:2381"
          }
        }
        # kube-proxy (nftables mode) defaults --nodeport-addresses to the node's
        # primary IP — here the private vRack IP — so NodePorts only answered on
        # the private NIC and the OVH IPLB (which hits the workers' PUBLIC IP)
        # got dead probes. Open NodePorts on every interface so the public NIC
        # serves 30443 too. metrics-bind-address likewise defaults to localhost;
        # bind :10249 to all interfaces for scraping (firewall-scoped below).
        # Generated into the kube-proxy DaemonSet by Talos (applies cluster-wide).
        proxy = {
          extraArgs = {
            "nodeport-addresses"   = "0.0.0.0/0"
            "metrics-bind-address" = "0.0.0.0"
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
      # Pod CIDR is allowed too: pod-to-node-IP on the same node skips the
      # flannel masquerade, so a pod scraping its own kubelet (e.g. metrics-server
      # colocated with the node it's scraping) keeps its pod-IP source and would
      # otherwise be dropped. Cross-node pod→kubelet still works via masquerade
      # but adding 10.244.0.0/16 makes self-hits work without depending on it.
      ingress:
        - subnet: ${var.private_network_cidr}
        - subnet: 10.244.0.0/16
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
    ,
    # Spegel peer-to-peer registry. Peers fetch image blobs from each other on
    # the registry host port (29999); 30021 is the node-port fallback mirror
    # target. Intra-cluster only — the libp2p router (5001) and metrics ride the
    # pod network. Without this the default-deny firewall silently kills sharing.
    <<-EOT
      apiVersion: v1alpha1
      kind: NetworkRuleConfig
      name: spegel-registry
      portSelector:
        ports:
          - 29999
          - 30021
        protocol: tcp
      ingress:
        - subnet: ${var.private_network_cidr}
    EOT
    ,
    # Control-plane component metrics (scraped by VMAgent on a worker, masqueraded
    # to its vRack IP). controller-manager :10257 + scheduler :10259 (HTTPS, authed),
    # etcd :2381 (HTTP, unauthed — vRack/pod-only is its only protection).
    <<-EOT
      apiVersion: v1alpha1
      kind: NetworkRuleConfig
      name: metrics-controlplane
      portSelector:
        ports:
          - 10257
          - 10259
          - 2381
        protocol: tcp
      ingress:
        - subnet: ${var.private_network_cidr}
        - subnet: 10.244.0.0/16
    EOT
    ,
    # Node-level metrics that also run on CPs: kube-proxy :10249 and the
    # node-exporter DaemonSet :9100 (both HTTP, unauthed). Pod CIDR is included
    # for the VMAgent self-hit case (same-node scrape skips flannel masquerade).
    <<-EOT
      apiVersion: v1alpha1
      kind: NetworkRuleConfig
      name: metrics-node
      portSelector:
        ports:
          - 10249
          - 9100
        protocol: tcp
      ingress:
        - subnet: ${var.private_network_cidr}
        - subnet: 10.244.0.0/16
    EOT
  ]
}
