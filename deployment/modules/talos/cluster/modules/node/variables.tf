variable "node_key" {
  type        = string
  description = "Node key (region identifier, e.g. 'lon')"
}

variable "node" {
  type = object({
    datacenter     = string
    plan_code      = string
    storage_option = string
    ram_option     = string
    vlan_ip        = string
    has_vrack      = optional(bool, true)
  })
  description = "Node configuration object"
}

variable "node_ip" {
  type        = string
  description = "Node public IP address"
}

variable "env" {
  type = string
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
