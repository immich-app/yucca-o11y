terraform {
  source = "."

  extra_arguments custom_vars {
    commands = get_terraform_commands_that_need_vars()
  }
}

locals {
  env   = get_env("TF_VAR_env")
  stage = get_env("TF_VAR_stage")

  # Node configurations per environment
  # Override via TF_VAR_nodes or environment-specific terragrunt
  nodes_by_env = {
    staging = {
      lon = {
        datacenter     = "lon"
        plan_code      = "24sys012"
        storage_option = "softraid-2x512nvme-24sys"
        ram_option     = "ram-32g-ecc-2666-24sys"
        vlan_ip        = "10.150.200.10"
      }
      rbx = {
        datacenter     = "rbx"
        plan_code      = "24sys012"
        storage_option = "softraid-2x512nvme-24sys"
        ram_option     = "ram-32g-ecc-2666-24sys"
        vlan_ip        = "10.150.200.11"
        has_vrack      = false
      }
      fra = {
        datacenter     = "fra"
        plan_code      = "24sys012"
        storage_option = "softraid-2x512nvme-24sys"
        ram_option     = "ram-32g-ecc-2666-24sys"
        vlan_ip        = "10.150.200.12"
      }
    }
    prod = {
      lon = {
        datacenter     = "lon"
        plan_code      = "24sys012"
        storage_option = "softraid-2x512nvme-24sys"
        ram_option     = "ram-32g-ecc-2666-24sys"
        vlan_ip        = "10.150.100.10"
      }
    }
    dev = {
      lon = {
        datacenter     = "lon"
        plan_code      = "24sys012"
        storage_option = "softraid-2x512nvme-24sys"
        ram_option     = "ram-32g-ecc-2666-24sys"
        vlan_ip        = "10.150.50.10"
      }
    }
  }
}

inputs = {
  nodes = lookup(local.nodes_by_env, local.env, {})
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "s3" {
    bucket = "${get_env("TF_VAR_tf_state_s3_bucket")}"
    key    = "yucca/o11y/ovh/account/${local.env}${local.stage != "" ? "/${local.stage}" : ""}"
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
