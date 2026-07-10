# TF-owned values consumed by Flux via postBuild substituteFrom (kubernetes/clusters/
# <env>/apps.yaml) — single source for anything both TF and the manifests need.
resource "kubernetes_config_map_v1" "bootstrap_settings" {
  depends_on = [helm_release.flux_operator]

  metadata {
    name      = "bootstrap-settings"
    namespace = "flux-system"
  }

  data = {
    BOOTSTRAP_MESH_DOMAIN          = var.netbird.mesh_dns_zone
    BOOTSTRAP_NETBIRD_GATEWAY_VIP  = var.netbird.gateway_vip
    BOOTSTRAP_NETBIRD_SERVICE_CIDR = var.netbird.service_cidr
    BOOTSTRAP_NETBIRD_EGRESS_CIDR  = var.netbird.egress_cidr
    BOOTSTRAP_NETBIRD_EGRESS_GW    = cidrhost(var.netbird.egress_cidr, 1)
    BOOTSTRAP_NETBIRD_DNS_IP       = local.netbird_dns_ip
  }
}
