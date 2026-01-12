variable "stage" {}
variable "env" {}

variable "ovh_application_key" {
  sensitive = true
}
variable "ovh_application_secret" {
  sensitive = true
}
variable "ovh_consumer_key" {
  sensitive = true
}

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
  description = "Map of node configurations keyed by region/location (e.g., lon, rbx)"
}

variable "vrack_name" {
  type        = string
  default     = "o11y"
  description = "Base name for the vRack"
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
