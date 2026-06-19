terraform {
  source = "."

  extra_arguments custom_vars {
    commands = get_terraform_commands_that_need_vars()
  }
}

locals {
  env   = get_env("TF_VAR_env")
  stage = get_env("TF_VAR_stage")

  # Worker spare-disk UserVolume selectors (see variables.tf). Both data volumes
  # use model + !system_disk; Talos spreads them across the non-system disks.
  worker_data_disk_match = lookup({
    staging    = "disk.model == \"WDC CL SN720 SDAQNTW-512G-2000\" && !system_disk"
    production = "disk.model == \"SAMSUNG MZQL21T9HCJR-00A07\" && !system_disk"
  }, local.env, "")

  # Second data volume only where there's a second spare (production).
  worker_data_disk2_match = lookup({
    production = "disk.model == \"SAMSUNG MZQL21T9HCJR-00A07\" && !system_disk"
  }, local.env, "")

  # Per-node worker NIC names (see variables.tf); re-provisioning a node onto
  # different hardware needs its entry updated here.
  worker_nics = lookup({
    staging = {
      rbx = { public = "eno1np0", private = "eno2np1" }
      gra = { public = "eno1np0", private = "eno2np1" }
      sbg = { public = "eno1np0", private = "eno2np1" }
    }
    production = {
      gra = { public = "eno1np0", private = "eno2np1" }
      rbx = { public = "enp4s0f0", private = "enp4s0f1" }
      sbg = { public = "enp4s0f0np0", private = "enp4s0f1np1" }
    }
  }, local.env, {})
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
  talos_installer_images  = dependency.ovh.outputs.talos_installer_images
  worker_data_disk_match  = local.worker_data_disk_match
  worker_data_disk2_match = local.worker_data_disk2_match
  worker_nics             = local.worker_nics
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
