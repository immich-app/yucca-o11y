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
