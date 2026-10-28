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

variable "op_connect_host" {
  type    = string
  default = "https://opc.o11y.futo.network"
}

variable "op_connect_token_write" {
  type      = string
  sensitive = true
}
