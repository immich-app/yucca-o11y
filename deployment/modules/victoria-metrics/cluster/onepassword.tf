# Publish the vmauth gateway URLs into the shared env vault so remote clusters
# can pull their endpoint from 1Password alongside the
# O11Y_VICTORIAMETRICS_VMAUTH_PASSWORD bearer token.
locals {
  # Mirrors the ENVIRONMENT_SHORT mapping in .mise/config.toml.
  env_short = var.env == "production" ? "prod" : var.env == "development" ? "dev" : var.env

  app_domain  = var.env == "production" ? "futostatus.com" : "${var.env}.futostatus.com"
  mesh_domain = var.env == "production" ? "o11y.futo.network" : "${var.env}.o11y.futo.network"
}

data "onepassword_vault" "shared_env" {
  name = "shared_tf_${local.env_short}"
}

resource "onepassword_item" "vmauth_mesh_url" {
  vault    = data.onepassword_vault.shared_env.uuid
  title    = "O11Y_VICTORIAMETRICS_VMAUTH_MESH_URL"
  category = "password"
  password = "https://vmauth.${local.mesh_domain}"
}

resource "onepassword_item" "vmauth_public_url" {
  vault    = data.onepassword_vault.shared_env.uuid
  title    = "O11Y_VICTORIAMETRICS_VMAUTH_PUBLIC_URL"
  category = "password"
  password = "https://vmauth.${local.app_domain}"
}
