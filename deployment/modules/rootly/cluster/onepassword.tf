# Publish the heartbeat ping credentials into the env vault so the
# rootly-heartbeat ExternalSecret can deliver them to the Grafana contact point.
locals {
  # Mirrors the ENVIRONMENT_SHORT mapping in .mise/config.toml.
  env_short = var.env == "production" ? "prod" : var.env == "development" ? "dev" : var.env
}

data "onepassword_vault" "env" {
  name = "o11y_tf_${local.env_short}"
}

# Dedicated Discord webhook for Rootly's alert workflows (not Grafana's).
data "onepassword_item" "discord_webhook" {
  vault = data.onepassword_vault.env.uuid
  title = "ROOTLY_DISCORD_WEBHOOK"
}

resource "onepassword_item" "heartbeat_ping_url" {
  vault    = data.onepassword_vault.env.uuid
  title    = "ROOTLY_HEARTBEAT_PING_URL"
  category = "password"
  password = rootly_heartbeat.grafana_alerting.ping_url
}

resource "onepassword_item" "heartbeat_ping_secret" {
  vault    = data.onepassword_vault.env.uuid
  title    = "ROOTLY_HEARTBEAT_PING_SECRET"
  category = "password"
  password = rootly_heartbeat.grafana_alerting.secret
}
