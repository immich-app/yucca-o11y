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

  config_patches = concat([
    yamlencode({
      machine = {
        # Install disk isn't pinned: OVH's BYOI provisioning picks the disk and
        # Talos keeps that install, so pinning here has no effect on production.
        # worker_disk is the real install target on staging (uniform hardware).
        install = {
          disk  = var.worker_disk
          image = var.talos_installer_images.bare_metal
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
        # Pin the kubelet node IP to the vRack (CPs already do): kubelet otherwise picks the
        # lowest 10.x host address — the Multus bridge IP once stole a worker's InternalIP.
        kubelet = {
          nodeIP = {
            validSubnets = [var.private_network_cidr]
          }
          # Explicit because Talos's CoreDNS is disabled (see controlplane.tf).
          clusterDNS = ["10.96.0.10"]
        }
        network = {
          # NIC names aren't uniform across OVH workers (even within a plan code),
          # so they're per-node via var.worker_nics. Port 0 = public (DHCP),
          # port 1 = private vRack (static).
          interfaces = [
            {
              interface = var.worker_nics[each.key].public
              dhcp      = true
            },
            {
              interface = var.worker_nics[each.key].private
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
    # Netbird overlay — the node management mesh. Operators reach the vRack IPs
    # via the Netbird route (server-side, masqueraded to a routing-peer's vRack
    # IP). NB_MANAGEMENT_URL is set explicitly to mirror yucca (Cloud default).
    <<-EOT
      name: netbird
      apiVersion: v1alpha1
      kind: ExtensionServiceConfig
      environment:
      - NB_SETUP_KEY=${var.netbird_setup_key}
      - NB_MANAGEMENT_URL=https://api.netbird.io
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
    # Primary spare-disk volume (var.worker_data_disk_match). With local-hostpath-2
    # using the same model + !system_disk selector, Talos spreads the two across
    # the non-system disks.
    <<-EOT
      apiVersion: v1alpha1
      kind: UserVolumeConfig
      name: local-hostpath
      provisioning:
        diskSelector:
          match: ${var.worker_data_disk_match}
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
      # otherwise be dropped. Cross-node pod→kubelet still works via masquerade.
      ingress:
        - subnet: ${var.private_network_cidr}
        - subnet: 10.244.0.0/16
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
    ,
    # Envoy data-plane NodePort, reached by the OVH IPLB on the worker's PUBLIC
    # IP (the lb1 order is vrackEligibility=false, so the LB can't ride the vRack
    # — see ovh/account/iplb.tf). Restricted to the IPLB's NAT/source range
    # (OVH /ipLoadbalancing/{svc}/natIp = 10.108.0.0/14; confirmed by packet
    # capture — the LB connects from 10.110.x.x in that block). Those are
    # OVH-internal private IPs, so the public internet can't reach 30443 directly
    # and can't spoof RFC1918 sources past OVH's edge — the LB is the only ingress
    # path. 30443 must match the Envoy Service nodePort.
    <<-EOT
      apiVersion: v1alpha1
      kind: NetworkRuleConfig
      name: envoy-nodeport
      portSelector:
        ports:
          - 30443
        protocol: tcp
      ingress:
        - subnet: 10.108.0.0/14
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
    # Node-level metrics on workers: kube-proxy :10249 (binds 0.0.0.0 via the
    # cluster-wide proxy config set on the CPs) and the node-exporter DaemonSet
    # :9100. Both HTTP/unauthed. Pod CIDR is included for the VMAgent self-hit
    # case — a worker scraping its own node skips the flannel masquerade.
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
    ], var.worker_data_disk2_match == "" ? [] : [
    # Second spare NVMe — production only (data2_match = "" renders nothing).
    <<-EOT
      apiVersion: v1alpha1
      kind: UserVolumeConfig
      name: local-hostpath-2
      provisioning:
        diskSelector:
          match: ${var.worker_data_disk2_match}
        minSize: 100GB
        grow: true
    EOT
  ])
}
