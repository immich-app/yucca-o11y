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
  default     = "0.45.0"
  description = "Flux operator chart version"
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
