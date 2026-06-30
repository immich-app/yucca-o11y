# Retained only to destroy the (now config-removed) tailnet keys; a provider must
# be present to delete its own resources. Remove this + config.tf + the vars in the
# follow-up once the keys are gone from state. (tailscale/account is unaffected.)
provider "tailscale" {
  # OAuth client from the o11y_tf vault. Must hold write on auth keys + read on
  # devices, and own the tag:project-yucca / tag:env-* tags it issues keys with.
  oauth_client_id     = var.tailscale_oauth_client_id
  oauth_client_secret = var.tailscale_oauth_client_secret
  tailnet             = var.tailscale_tailnet_id
}
