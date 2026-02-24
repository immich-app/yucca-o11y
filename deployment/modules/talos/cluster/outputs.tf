output "clusters" {
  description = "Map of cluster configurations for downstream modules"
  value = {
    for k, v in module.node : k => v.cluster
  }
  sensitive = true
}

output "kubernetes_client_configurations" {
  description = "Map of kubernetes client configurations for each cluster"
  value = {
    for k, v in module.node : k => v.kubernetes_client_configuration
  }
  sensitive = true
}

output "talos_client_configurations" {
  value = {
    for k, v in module.node : k => v.talos_client_configuration
  }
  sensitive = true
}
