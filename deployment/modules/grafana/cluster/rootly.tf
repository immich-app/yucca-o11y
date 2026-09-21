# Service account for Rootly's Grafana integration (Integrations > Grafana in
# Rootly), which has no API or Terraform surface: it is installed by hand with
# this cluster's Grafana URL and the token below, read from the env vault.
# Rootly requires Admin to take dashboard snapshots during incidents.
#
# This lives apart from the rootly/cluster module on purpose: that module must
# stay plannable while Grafana is down, since Grafana being down is what its
# heartbeat reports.
locals {
  grafana_url = var.env == "production" ? "https://grafana.futostatus.com" : "https://grafana.${var.env}.futostatus.com"
}

resource "grafana_service_account" "rootly" {
  name        = "rootly"
  role        = "Admin"
  is_disabled = false
}

resource "grafana_service_account_token" "rootly" {
  name               = "rootly-integration"
  service_account_id = grafana_service_account.rootly.id
}
