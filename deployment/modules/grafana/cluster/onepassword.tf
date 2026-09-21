# Reads the Grafana admin password the cluster's ExternalSecret also consumes,
# and publishes the Rootly service account token next to it so the Rootly
# integration can be configured from the vault rather than from kubectl.
locals {
  # Mirrors the ENVIRONMENT_SHORT mapping in .mise/config.toml.
  env_short = var.env == "production" ? "prod" : var.env == "development" ? "dev" : var.env
}

data "onepassword_vault" "env" {
  name = "o11y_tf_${local.env_short}"
}

data "onepassword_item" "grafana_admin_password" {
  vault = data.onepassword_vault.env.uuid
  title = "GRAFANA_ADMIN_PASSWORD"
}

resource "onepassword_item" "rootly_service_account_token" {
  vault    = data.onepassword_vault.env.uuid
  title    = "ROOTLY_GRAFANA_SERVICE_ACCOUNT_TOKEN"
  category = "password"
  password = grafana_service_account_token.rootly.key
}
