# Per-env o11y NetBird objects (state key .../netbird/cluster/<env>). Everything is
# per-env — resource groups and policies included — so access can differ by env
# (Zack: some people get dev/staging but not prod). No account-wide layer.
#
# Object names are rfc1123 (lowercase-hyphen). Exception: the setup keys keep their
# original UPPER_SNAKE names — renaming a key is RequiresReplace (new key value), which
# cascades into talos machine configs + the router Secret; rename at the next rotation.

# Existing account-wide users group (yucca peers — populated via users' auto_groups,
# per NetBird's model). Referenced as the policy source so the same operators that
# reach yucca also reach o11y — per the team decision.
data "netbird_group" "yucca" {
  name = "yucca"
}

# Group the Talos nodes auto-join via the setup key below.
resource "netbird_group" "talos" {
  name = "o11y-${var.env}-talos"
}

# Per-env tag for this cluster's routed resources (the vRack subnet below tags into
# it; the yucca->resource policy grants it).
resource "netbird_group" "o11y_resource" {
  name = "o11y-${var.env}-resource"
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
  name        = "o11y-${var.env}-vrack"
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
  name    = "o11y-${var.env}-vrack-cidr"
  address = var.private_network_cidr
  groups  = [netbird_group.o11y_resource.id]
  enabled = true
}

# NetBird default-denies; allow yucca to reach this env's routed subnet on the Talos
# management ports (apid + kube-apiserver).
resource "netbird_policy" "yucca_to_o11y_resource" {
  name    = "o11y-${var.env}-yucca-to-resource"
  enabled = true

  rule {
    name          = "yucca-to-o11y-resource"
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

  # Registered in netbox/cluster; published to Flux via the bootstrap-settings ConfigMap.
  netbird_service_cidr = var.env == "production" ? "10.69.0.0/24" : "10.69.1.0/24"
  netbird_gateway_vip  = cidrhost(local.netbird_service_cidr, 10)
}

resource "netbird_group" "k8s_routing_peers" {
  name = "o11y-${var.env}-k8s-routing-peers"
}

resource "netbird_group" "k8s_gateway" {
  name = "o11y-${var.env}-k8s-gateway"
}

resource "netbird_network" "k8s" {
  name        = "o11y-${var.env}-k8s"
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
  name       = "o11y-${var.env}-k8s-gateway"
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

# Distributed to the router pods too — they serve NetBird DNS to the cluster
# (CoreDNS forwards futo.network).
resource "netbird_dns_zone" "mesh" {
  name                 = local.mesh_dns_zone
  domain               = local.mesh_dns_zone
  enabled              = true
  enable_search_domain = false
  distribution_groups  = [data.netbird_group.yucca.id, netbird_group.k8s_routing_peers.id]
}

# Wildcard A -> the gateway VIP (HA is the >=2 routing Pods, not multiple records).
resource "netbird_dns_record" "mesh_wildcard" {
  zone_id = netbird_dns_zone.mesh.id
  name    = "*.${local.mesh_dns_zone}"
  type    = "A"
  content = local.netbird_gateway_vip
  ttl     = 300
}

# Allow yucca peers to reach the gateway VIP: 443 for workloads, 6443 for the HA
# kube-apiserver endpoint (Envoy TLS-passthrough; see mesh-gateway-api).
resource "netbird_policy" "yucca_to_k8s_gateway" {
  name    = "o11y-${var.env}-yucca-to-k8s-gateway"
  enabled = true

  rule {
    name          = "yucca-to-k8s-gateway"
    action        = "accept"
    protocol      = "tcp"
    enabled       = true
    bidirectional = false
    sources       = [data.netbird_group.yucca.id]
    destinations  = [netbird_group.k8s_gateway.id]
    ports         = ["443", "6443"]
  }
}

# opc egress: pods with a Multus leg in this range (netbird-egress NAD) reach the bootstrap
# 1Password Connect. The nodes advertise it, so NetBird's own rules masquerade it out wt0 —
# pod-CIDR traffic would be dropped.
locals {
  # Registered in netbox/cluster; published to Flux via the bootstrap-settings ConfigMap.
  netbird_egress_cidr = var.env == "production" ? "10.69.2.0/24" : "10.69.3.0/24"
}

resource "netbird_network" "k8s_egress" {
  name        = "o11y-${var.env}-k8s-egress"
  description = "o11y ${var.env} pod egress range (Multus netbird-egress NAD)"
}

resource "netbird_network_router" "k8s_egress" {
  network_id  = netbird_network.k8s_egress.id
  peer_groups = [netbird_group.talos.id]
  masquerade  = true
  metric      = 9999
  enabled     = true
}

# In o11y_resource: NetBird only programs routers for resources a policy references
# (a policy-less group left every node unprogrammed). The yucca 50000/6443 grant is inert here.
resource "netbird_network_resource" "k8s_egress" {
  network_id = netbird_network.k8s_egress.id
  name       = "o11y-${var.env}-k8s-egress-cidr"
  address    = local.netbird_egress_cidr
  groups     = [netbird_group.o11y_resource.id]
  enabled    = true
}

# CI peers (GitHub Actions runners): the infra workflow joins the mesh to reach the
# talos + kube APIs for plan/apply. The key is read from this module's state by the
# workflow; it never lands in 1Password. Ephemeral: runners are transient.
resource "netbird_group" "ci" {
  name = "o11y-${var.env}-ci"
}

resource "netbird_setup_key" "ci" {
  name           = "o11y-${var.env}-ci"
  type           = "reusable"
  ephemeral      = true
  auto_groups    = [netbird_group.ci.id]
  expiry_seconds = 0
  usage_limit    = 0
}

resource "netbird_policy" "ci_to_o11y_resource" {
  name    = "o11y-${var.env}-ci-to-resource"
  enabled = true

  rule {
    name          = "ci-to-o11y-resource"
    action        = "accept"
    protocol      = "tcp"
    enabled       = true
    bidirectional = false
    sources       = [netbird_group.ci.id]
    destinations  = [netbird_group.o11y_resource.id]
    ports         = ["50000", "6443"]
  }
}

# Bootstrap-owned group holding the opc resource (live account name — verify if it changes).
data "netbird_group" "bootstrap_opc" {
  name = "bootstrap-resources"
}

# Egress leaves masqueraded as the node peer -> nodes are the source; also pushes them the opc /32 route.
resource "netbird_policy" "talos_to_bootstrap_opc" {
  name    = "o11y-${var.env}-talos-to-bootstrap-opc"
  enabled = true

  rule {
    name          = "talos-to-bootstrap-opc"
    action        = "accept"
    protocol      = "tcp"
    enabled       = true
    bidirectional = false
    sources       = [netbird_group.talos.id]
    destinations  = [data.netbird_group.bootstrap_opc.id]
    ports         = ["443"]
  }
}
