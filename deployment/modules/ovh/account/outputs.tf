output "clusters" {
  description = "Map of cluster configurations for downstream modules"
  value = {
    for k, v in var.nodes : k => {
      name               = "o11y-${var.env}-${k}"
      endpoint           = "https://${data.tailscale_device.nodes[k].addresses[0]}:6443"
      ip                 = ovh_dedicated_server.node[k].ip
      tailscale_ip       = data.tailscale_device.nodes[k].addresses[0]
      client_certificate = talos_cluster_kubeconfig.nodes[k].kubernetes_client_configuration.client_certificate
      client_key         = talos_cluster_kubeconfig.nodes[k].kubernetes_client_configuration.client_key
      ca_certificate     = talos_cluster_kubeconfig.nodes[k].kubernetes_client_configuration.ca_certificate
    }
  }
  sensitive = true
}

output "node_ips" {
  description = "Map of node IPs keyed by region"
  value       = { for k, v in ovh_dedicated_server.node : k => v.ip }
}

output "kubernetes_client_configurations" {
  description = "Map of kubernetes client configurations for each cluster"
  value = {
    for k, v in talos_cluster_kubeconfig.nodes : k => v.kubernetes_client_configuration
  }
  sensitive = true
}

