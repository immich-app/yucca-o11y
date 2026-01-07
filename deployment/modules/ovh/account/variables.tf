variable "stage" {}
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

variable "tailscale_api_key" {
  sensitive = true
}
variable "tailscale_tailnet_id" {
  sensitive = true
}
