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

dependency "ovh" {
  config_path = "../../ovh/account"

  # Mocks need ≥1 CP entry — main.tf reads local.controlplane_keys[0] for the
  # bootstrap node, which would fail on an empty map before ovh has applied.
  mock_outputs = {
    controlplane_nodes = {
      mock = {
        name       = "o11y-mock-cp"
        region     = "RBX"
        public_ip  = "192.0.2.10"
        private_ip = "10.150.200.10"
      }
    }
    worker_nodes         = {}
    private_network_cidr = "10.150.200.0/24"
    talos_installer_images = {
      bare_metal   = "factory.talos.dev/metal-installer/mock:v1.13.0"
      public_cloud = "factory.talos.dev/openstack-installer/mock:v1.13.0"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

dependency "tailscale" {
  config_path = "../../tailscale/account"
  mock_outputs = {
    tailscale_output = "mock-tailscale-output"
  }
}

inputs = {
  controlplane_nodes     = dependency.ovh.outputs.controlplane_nodes
  worker_nodes           = dependency.ovh.outputs.worker_nodes
  private_network_cidr   = dependency.ovh.outputs.private_network_cidr
  talos_installer_images = dependency.ovh.outputs.talos_installer_images
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "s3" {
    bucket = "${get_env("TF_VAR_tf_state_s3_bucket")}"
    key    = "yucca/o11y/v3/talos/cluster/${local.env}${local.stage != "" ? "/${local.stage}" : ""}"
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
