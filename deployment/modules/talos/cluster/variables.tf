variable "env" {}
variable "stage" {}

variable "tailscale_api_key" {
  sensitive = true
}
variable "tailscale_tailnet_id" {
  sensitive = true
}

variable "nodes" {
  type = map(object({
    datacenter     = string
    plan_code      = string
    storage_option = string
    ram_option     = string
    vlan_ip        = string
    has_vrack      = optional(bool, true)
  }))
  description = "Map of node configurations keyed by region"
}

variable "node_ips" {
  type        = map(string)
  description = "Map of node public IPs keyed by region (from ovh/account)"
}

variable "talos_version" {
  type        = string
  default     = "v1.12.4"
  description = "Talos version to deploy"
}

variable "talos_schematic_id" {
  type        = string
  default     = "4a0d65c669d46663f377e7161e50cfd570c401f26fd9e7bda34a0216b6f1922b"
  description = "Talos image factory schematic ID"
}
