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

output "controlplane_tailscale_ips" {
  value = {
    for k, _ in var.controlplane_nodes :
    k => data.tailscale_device.controlplane[k].addresses[0]
  }
}

output "talos_client_configuration" {
  sensitive = true
  value     = data.talos_client_configuration.this.talos_config
}

output "kubeconfig" {
  sensitive = true
  value     = talos_cluster_kubeconfig.this.kubeconfig_raw
}
