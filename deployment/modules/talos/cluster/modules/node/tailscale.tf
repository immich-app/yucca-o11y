resource "tailscale_tailnet_key" "this" {
  reusable            = true
  ephemeral           = true
  preauthorized       = true
  recreate_if_invalid = "always"
  expiry              = 7776000
  description         = "Talos key o11y-${var.env}-${var.node_key}"
}

data "tailscale_device" "this" {
  hostname = "o11y-${var.env}-${var.node_key}"
  wait_for = "300s"

  depends_on = [
    talos_machine_bootstrap.this
  ]
}
