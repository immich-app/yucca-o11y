variable "env" {}
variable "stage" {}

variable "tf_state_s3_bucket" {}
variable "tf_state_s3_region" {}
variable "tf_state_s3_access_key" {}
variable "tf_state_s3_secret_key" {}
variable "tf_state_s3_endpoint" {}

variable "cluster" {
  type = object({
    name               = string
    endpoint           = string
    operator_endpoint  = string
    vip                = string
    client_certificate = string
    client_key         = string
    ca_certificate     = string
  })
  sensitive = true
}

variable "envoy_ip" {
  type = string
}

variable "envoy_ip_block" {
  type = string
}

variable "flux_operator_version" {
  type    = string
  default = "0.50.0"
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
