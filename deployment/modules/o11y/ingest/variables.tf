variable "env" {}

variable "app_domain" {
  type        = string
  description = "Public domain the vmauth gateway is published on."
  default     = "futostatus.com"
}

variable "op_connect_host" {
  type    = string
  default = "https://opc.o11y.futo.network"
}

variable "op_connect_token_write" {
  type      = string
  sensitive = true
}
