variable "env" {}
variable "stage" {}

variable "tailscale_api_key" {
  sensitive = true
}
variable "tailscale_tailnet_id" {
  sensitive = true
}
