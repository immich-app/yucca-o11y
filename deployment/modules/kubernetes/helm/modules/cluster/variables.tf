variable "cluster_name" {
  type        = string
  description = "Name of the cluster"
}

variable "env" {
  type        = string
  description = "Environment name (e.g. staging, production)"
}

variable "flux_operator_version" {
  type        = string
  default     = "0.45.0"
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

variable "vmauth_external_reader_password" {
  type      = string
  sensitive = true
}

variable "vmauth_external_writer_password" {
  type      = string
  sensitive = true
}

variable "vmauth_internal_reader_password" {
  type      = string
  sensitive = true
}

variable "vmauth_internal_writer_password" {
  type      = string
  sensitive = true
}

variable "ovh_application_key" {
  type      = string
  sensitive = true
}

variable "ovh_application_secret" {
  type      = string
  sensitive = true
}

variable "ovh_consumer_key" {
  type      = string
  sensitive = true
}

variable "op_credentials_file" {
  type      = string
  sensitive = true
}

variable "op_connect_token" {
  type      = string
  sensitive = true
}

variable "op_connect_token_env" {
  type      = string
  sensitive = true
}
