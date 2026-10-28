# The cluster's glitchtip-s3 ExternalSecret reads these from the env vault.
locals {
  # Mirrors the ENVIRONMENT_SHORT mapping in .mise/config.toml.
  env_short = var.env == "production" ? "prod" : var.env == "development" ? "dev" : var.env
}

data "onepassword_vault" "env" {
  name = "o11y_tf_${local.env_short}"
}

resource "onepassword_item" "glitchtip_s3_access_key_id" {
  vault    = data.onepassword_vault.env.uuid
  title    = "GLITCHTIP_S3_ACCESS_KEY_ID"
  category = "password"
  password = ovh_cloud_project_user_s3_credential.glitchtip.access_key_id
}

resource "onepassword_item" "glitchtip_s3_secret_access_key" {
  vault    = data.onepassword_vault.env.uuid
  title    = "GLITCHTIP_S3_SECRET_ACCESS_KEY"
  category = "password"
  password = ovh_cloud_project_user_s3_credential.glitchtip.secret_access_key
}
