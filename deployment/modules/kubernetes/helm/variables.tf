variable "env" {}
variable "stage" {}

variable "tf_state_s3_bucket" {}
variable "tf_state_s3_region" {}
variable "tf_state_s3_access_key" {}
variable "tf_state_s3_secret_key" {}
variable "tf_state_s3_endpoint" {}

variable "clusters" {
  type = map(object({
    name               = string
    endpoint           = string
    ip                 = string
    tailscale_ip       = string
    client_certificate = string
    client_key         = string
    ca_certificate     = string
  }))
  description = "Map of cluster configurations from ovh/account module"
}

variable "flux_operator_version" {
  type        = string
  default     = "0.43.0"
  description = "Flux operator chart version"
}

