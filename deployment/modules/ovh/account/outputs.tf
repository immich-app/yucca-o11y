output "node_ips" {
  description = "Map of node IPs keyed by region"
  value       = { for k, v in ovh_dedicated_server.node : k => v.ip }
}

output "installer_image" {
  description = "Talos installer image URL"
  value       = data.talos_image_factory_urls.this.urls.installer
}

output "nodes" {
  description = "Node configuration map passed through for downstream modules"
  value       = var.nodes
}
