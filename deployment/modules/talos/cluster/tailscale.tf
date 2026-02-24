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
