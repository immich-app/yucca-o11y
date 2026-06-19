variable "tailscale_oauth_client_id" {
  sensitive = true
}
variable "tailscale_oauth_client_secret" {
  sensitive = true
}
variable "tailscale_tailnet_id" {
  sensitive = true
}

# CIDRs must match each env's `private_network_cidr` in
# deployment/modules/ovh/account/terragrunt.hcl.
variable "subnet_routes_by_env" {
  type = map(string)
  default = {
    development = "10.150.50.0/24"
    staging     = "10.150.200.0/24"
    production  = "10.150.100.0/24"
  }
}
