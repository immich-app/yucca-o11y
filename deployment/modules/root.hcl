locals {
  env   = get_env("TF_VAR_env")
  stage = get_env("TF_VAR_stage")
}

# Per-env working dirs, so switching ENVIRONMENT never reuses another env's
# initialized backend (including the copies dependency outputs are read from).
# The stage is hashed: a raw one containing "/../" can resolve into another
# env's directory.
download_dir = "${get_terragrunt_dir()}/.terragrunt-cache/${local.env}${local.stage != "" ? "-${sha256(local.stage)}" : ""}"

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  # The contents carry the state bucket keys. A mutable file is written in
  # place instead of being stored in Terragrunt's persistent CAS and
  # hard-linked here, so no copy outlives download_dir.
  mutable  = true
  contents = <<EOF
terraform {
  backend "s3" {
    bucket = "${get_env("TF_VAR_tf_state_s3_bucket")}"
    key    = "yucca/o11y/v3/${path_relative_to_include()}/${local.env}${local.stage != "" ? "/${local.stage}" : ""}"
    region = "${get_env("TF_VAR_tf_state_s3_region")}"
    access_key = "${get_env("TF_VAR_tf_state_s3_access_key")}"
    secret_key = "${get_env("TF_VAR_tf_state_s3_secret_key")}"

    endpoints = {
      s3 = "${get_env("TF_VAR_tf_state_s3_endpoint")}"
    }

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
  }
}
EOF
}
