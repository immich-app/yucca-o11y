output "cluster" {
  sensitive = true
  value = {
    name               = local.cluster_name
    endpoint           = local.cluster_endpoint
    operator_endpoint  = local.operator_endpoint
    vip                = local.controlplane_vip
    client_certificate = talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_certificate
    client_key         = talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_key
    ca_certificate     = talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate
  }
}

output "talos_client_configuration" {
  sensitive = true
  value     = data.talos_client_configuration.this.talos_config
}

# Server rewritten from the (in-cluster-only) VIP to the HA mesh endpoint, so the zone
# special-case lives only in netbird/cluster's mesh_dns_zone. Break-glass for bootstrap/DR
# before the gateway exists: kubectl --server=https://<cp-private-ip>:6443 (all cert SANs).
output "kubeconfig" {
  sensitive = true
  value = replace(
    talos_cluster_kubeconfig.this.kubeconfig_raw,
    "server: ${local.cluster_endpoint}",
    "server: https://kube.${var.mesh_dns_zone}:6443",
  )
}
