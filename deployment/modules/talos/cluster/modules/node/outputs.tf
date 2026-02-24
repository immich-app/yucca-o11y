output "cluster" {
  description = "Cluster configuration for this node"
  value = {
    name               = "o11y-${var.env}-${var.node_key}"
    endpoint           = "https://${data.tailscale_device.this.addresses[0]}:6443"
    ip                 = var.node_ip
    tailscale_ip       = data.tailscale_device.this.addresses[0]
    client_certificate = talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_certificate
    client_key         = talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_key
    ca_certificate     = talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate
  }
  sensitive = true
}

output "kubernetes_client_configuration" {
  description = "Kubernetes client configuration for this node"
  value       = talos_cluster_kubeconfig.this.kubernetes_client_configuration
  sensitive   = true
}

output "talos_client_configuration" {
  description = "Talos client configuration for this node"
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}
