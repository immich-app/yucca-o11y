output "clusters" {
  description = "Map of cluster configurations for downstream modules"
  value = {
    for k, v in var.nodes : k => {
      name               = "o11y-${var.env}-${k}"
      endpoint           = "https://${data.tailscale_device.nodes[k].addresses[0]}:6443"
      ip                 = var.node_ips[k]
      tailscale_ip       = data.tailscale_device.nodes[k].addresses[0]
      client_certificate = talos_cluster_kubeconfig.nodes[k].kubernetes_client_configuration.client_certificate
      client_key         = talos_cluster_kubeconfig.nodes[k].kubernetes_client_configuration.client_key
      ca_certificate     = talos_cluster_kubeconfig.nodes[k].kubernetes_client_configuration.ca_certificate
    }
  }
  sensitive = true
}

output "kubernetes_client_configurations" {
  description = "Map of kubernetes client configurations for each cluster"
  value = {
    for k, v in talos_cluster_kubeconfig.nodes : k => v.kubernetes_client_configuration
  }
  sensitive = true
}

output "talos_client_configurations" {
  value = {
    for k, v in data.talos_client_configuration.nodes : k => v.talos_config
  }
  sensitive = true
}
