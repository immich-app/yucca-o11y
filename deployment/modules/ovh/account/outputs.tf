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

# output "loadbalancer_ip" {
#   description = "Public IPv4 of the OVH IP Load Balancer"
#   value       = ovh_iploadbalancing.this.ipv4
# }

# output "loadbalancer_service_name" {
#   description = "Service name of the OVH IP Load Balancer"
#   value       = ovh_iploadbalancing.this.service_name
# }
