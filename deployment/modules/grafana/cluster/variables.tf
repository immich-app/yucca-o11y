variable "env" {}

variable "grafana_admin_user" {
  type    = string
  default = "admin"
}

variable "op_connect_host" {
  type    = string
  default = "https://opc.o11y.futo.network"
}

variable "op_connect_token_write" {
  type      = string
  sensitive = true
}
