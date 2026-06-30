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

# NetBird default-denies; allow yucca operators to reach THIS env's routed subnet on
# the Talos management ports only (apid + kube-apiserver). Per-env policy so access
# can later differ by env — tighter than yucca's all-protocol yucca->yucca_resource.
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
