resource "tailscale_tailnet_key" "nodes" {
  for_each            = var.nodes
  reusable            = true
  ephemeral           = true
  preauthorized       = true
  recreate_if_invalid = "always"
  expiry              = 7776000
  description         = "Talos key o11y-${var.env}-${each.key}"
}

data "tailscale_device" "nodes" {
  for_each = var.nodes
  hostname = "o11y-${var.env}-${each.key}"
  wait_for = "300s"

  depends_on = [
    talos_machine_bootstrap.nodes
  ]
}

resource "tailscale_tailnet_settings" "org" {
  acls_externally_managed_on                  = true
  acls_external_link                          = "https://github.com/octocat/Hello-World"
  devices_approval_on                         = true
  devices_auto_updates_on                     = true
  devices_key_duration_days                   = 5
  users_approval_on                           = true
  users_role_allowed_to_join_external_tailnet = "member"
  posture_identity_collection_on              = true
  https_enabled                               = true
}
