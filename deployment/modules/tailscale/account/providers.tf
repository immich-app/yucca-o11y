provider "tailscale" {
  # OAuth client from the o11y_tf vault. Must hold write on the tailnet policy file.
  oauth_client_id     = var.tailscale_oauth_client_id
  oauth_client_secret = var.tailscale_oauth_client_secret
  tailnet             = var.tailscale_tailnet_id
}
