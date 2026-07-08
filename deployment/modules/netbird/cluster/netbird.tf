# Per-env o11y NetBird objects (state key .../netbird/cluster/<env>). Everything is
# per-env — resource groups and policies included — so access can differ by env
# (Zack: some people get dev/staging but not prod). No account-wide layer.
#
# All object names are UPPER_SNAKE to match yucca's convention (groups, setup keys,
# networks, network resources, and policies/rules).

# Existing account-wide users group (yucca peers — populated via users' auto_groups,
# per NetBird's model). Referenced as the policy source so the same operators that
# reach yucca also reach o11y — per the team decision.
data "netbird_group" "yucca" {
  name = "yucca"
}

# Group the Talos nodes auto-join via the setup key below.
resource "netbird_group" "talos" {
  name = "O11Y_${upper(var.env)}_TALOS"
}

# Per-env tag for this cluster's routed resources (the vRack subnet below tags into
# it; the yucca->resource policy grants it). Created with its final name — the
# NetBird provider can't rename a group once network resources are tagged into it.
resource "netbird_group" "o11y_resource" {
  name = "O11Y_${upper(var.env)}_RESOURCE"
}

# Reusable, non-ephemeral enrollment key for the Talos nodes — fed to the netbird
# Talos extension as NB_SETUP_KEY. NOT ephemeral: ephemeral peers are reaped after
# 10m idle, which would delete live nodes.
resource "netbird_setup_key" "talos" {
  name           = "O11Y_${upper(var.env)}_TALOS"
  type           = "reusable"
  ephemeral      = false
  expiry_seconds = 0 # unlimited — nodes re-enroll with the same key on reprovision
  usage_limit    = 0 # unlimited
  auto_groups    = [netbird_group.talos.id]
}

# vRack subnet advertised to operators with the Talos nodes as routing peers — the
# Netbird "Networks" model. Every node sits on the vRack, so any can route (HA);
# masquerade NATs operator traffic to the routing peer's vRack IP, which the node
# firewall already trusts.
resource "netbird_network" "vrack" {
  name        = "O11Y_${upper(var.env)}_VRACK"
  description = "o11y ${var.env} vRack private subnet"
}

resource "netbird_network_router" "vrack" {
  network_id  = netbird_network.vrack.id
  peer_groups = [netbird_group.talos.id]
  masquerade  = true
  metric      = 9999
  enabled     = true
}

resource "netbird_network_resource" "vrack" {
  network_id = netbird_network.vrack.id
  # Per-env: Netbird network-resource names are account-globally unique.
  name    = "O11Y_${upper(var.env)}_VRACK_CIDR"
  address = var.private_network_cidr
  groups  = [netbird_group.o11y_resource.id]
  enabled = true
}

# NetBird default-denies; allow yucca to reach this env's routed subnet on the Talos
# management ports (apid + kube-apiserver).
resource "netbird_policy" "yucca_to_o11y_resource" {
  name    = "O11Y_${upper(var.env)}_YUCCA_TO_RESOURCE"
  enabled = true

  rule {
    name          = "YUCCA_TO_O11Y_RESOURCE"
    action        = "accept"
    protocol      = "tcp"
    enabled       = true
    bidirectional = false
    sources       = [data.netbird_group.yucca.id]
    destinations  = [netbird_group.o11y_resource.id]
    ports         = ["50000", "6443"]
  }
}

# Mesh workload ingress. Routing peers are in-cluster Pods (netbird-router), not the Talos
# nodes: only Pod routing can advertise a Service ClusterIP (kube-proxy's DNAT runs in the
# host netns, after the Pod's netfilter matches the /32).
locals {
  mesh_dns_zone = var.env == "production" ? "o11y.futo.network" : "${var.env}.o11y.futo.network"

  # NetBox-allocated VIP; must equal the NETBIRD_GATEWAY_VIP cluster-setting.
  netbird_gateway_vip = var.env == "production" ? "10.69.0.10" : "10.69.1.10"
}

resource "netbird_group" "k8s_routing_peers" {
  name = "O11Y_${upper(var.env)}_K8S_ROUTING_PEERS"
}

resource "netbird_group" "k8s_gateway" {
  name = "O11Y_${upper(var.env)}_K8S_GATEWAY"
}

resource "netbird_network" "k8s" {
  name        = "O11Y_${upper(var.env)}_K8S"
  description = "o11y ${var.env} in-cluster workload ingress (Envoy gateway)"
}

resource "netbird_network_router" "k8s" {
  network_id  = netbird_network.k8s.id
  peer_groups = [netbird_group.k8s_routing_peers.id]
  masquerade  = true
  metric      = 9999
  enabled     = true
}

# The Envoy gateway VIP as a /32 (mesh-gateway/service.yaml) — peers reach only this IP.
resource "netbird_network_resource" "k8s_gateway" {
  network_id = netbird_network.k8s.id
  name       = "O11Y_${upper(var.env)}_K8S_GATEWAY"
  address    = "${local.netbird_gateway_vip}/32"
  groups     = [netbird_group.k8s_gateway.id]
  enabled    = true
}

# Reusable, ephemeral enrolment key for the router Pods; output -> kubernetes/helm ->
# the netbird-setup-key Secret.
resource "netbird_setup_key" "k8s_routing_peer" {
  name           = "O11Y_${upper(var.env)}_K8S_ROUTING_PEER"
  type           = "reusable"
  ephemeral      = true
  auto_groups    = [netbird_group.k8s_routing_peers.id]
  expiry_seconds = 0
  usage_limit    = 0
}

# DNS zone; must match the MESH_DOMAIN cluster-setting.
resource "netbird_dns_zone" "mesh" {
  name                 = local.mesh_dns_zone
  domain               = local.mesh_dns_zone
  enabled              = true
  enable_search_domain = false
  distribution_groups  = [data.netbird_group.yucca.id]
}

# Wildcard A -> the gateway VIP (HA is the >=2 routing Pods, not multiple records).
resource "netbird_dns_record" "mesh_wildcard" {
  zone_id = netbird_dns_zone.mesh.id
  name    = "*.${local.mesh_dns_zone}"
  type    = "A"
  content = local.netbird_gateway_vip
  ttl     = 300
}

# Allow yucca peers to reach the gateway VIP over HTTPS.
resource "netbird_policy" "yucca_to_k8s_gateway" {
  name    = "O11Y_${upper(var.env)}_YUCCA_TO_K8S_GATEWAY"
  enabled = true

  rule {
    name          = "YUCCA_TO_K8S_GATEWAY"
    action        = "accept"
    protocol      = "tcp"
    enabled       = true
    bidirectional = false
    sources       = [data.netbird_group.yucca.id]
    destinations  = [netbird_group.k8s_gateway.id]
    ports         = ["443"]
  }
}
