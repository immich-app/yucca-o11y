provider "tailscale" {
  api_key = var.tailscale_api_key
  tailnet = var.tailscale_tailnet_id
}
