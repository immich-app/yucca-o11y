terraform {
  source = "."

  extra_arguments custom_vars {
    commands = get_terraform_commands_that_need_vars()
  }
}

locals {
  env   = get_env("TF_VAR_env")
  stage = get_env("TF_VAR_stage")
}

dependency "talos" {
  config_path = "../../talos/cluster"

  # Cert mocks must be valid base64 — providers.tf base64-decodes on every plan.
  mock_outputs = {
    cluster = {
      name               = "mock"
      endpoint           = "https://mock:6443"
      operator_endpoint  = "https://mock:6443"
      vip                = "10.0.0.5"
      client_certificate = "bW9jaw=="
      client_key         = "bW9jaw=="
      ca_certificate     = "bW9jaw=="
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "ovh" {
  config_path = "../../ovh/account"

  mock_outputs = {
    envoy_ip       = "1.2.3.4"
    envoy_ip_block = "1.2.3.4/30"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  cluster        = dependency.talos.outputs.cluster
  envoy_ip       = dependency.ovh.outputs.envoy_ip
  envoy_ip_block = dependency.ovh.outputs.envoy_ip_block
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "s3" {
    bucket = "${get_env("TF_VAR_tf_state_s3_bucket")}"
    key    = "yucca/o11y/v3/kubernetes/helm/${local.env}${local.stage != "" ? "/${local.stage}" : ""}"
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
