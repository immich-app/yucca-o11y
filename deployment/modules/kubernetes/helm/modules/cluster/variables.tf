variable "cluster_name" {
  type        = string
  description = "Name of the cluster"
}

variable "flux_operator_version" {
  type        = string
  default     = "0.37.1"
  description = "Flux operator chart version"
}

variable "flux_instance_values_file" {
  type        = string
  description = "Path to flux instance values file"
}

variable "other_node_ips" {
  type        = list(string)
  description = "Tailscale IPs of the other nodes in the environment (sorted by key)"
}

variable "vmauth_reader_password" {
  type      = string
  sensitive = true
}

variable "vmauth_writer_password" {
  type      = string
  sensitive = true
}

variable "vmauth_internal_reader_password" {
  type      = string
  sensitive = true
}

variable "vmagent_password" {
  type      = string
  sensitive = true
}
