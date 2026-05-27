terraform {
  source = "."

  extra_arguments custom_vars {
    commands = get_terraform_commands_that_need_vars()
  }
}

locals {
  env   = get_env("TF_VAR_env")
  stage = get_env("TF_VAR_stage")

  topology_by_env = {
    staging = {
      controlplane_nodes = {
        rbx = {
          region      = "RBX-A"
          flavor_name = "b3-8"
          private_ip  = "10.150.200.10"
        }
        gra = {
          region      = "GRA9"
          flavor_name = "b3-8"
          private_ip  = "10.150.200.11"
        }
        par = {
          region      = "EU-WEST-PAR"
          flavor_name = "b3-8"
          private_ip  = "10.150.200.12"
        }
      }
      worker_nodes = {
        rbx = {
          datacenter              = "rbx"
          plan_code               = "24sys022"
          storage_option          = "softraid-2x512nvme-24sys"
          ram_option              = "ram-32g-ecc-2133-24sys"
          bandwidth_option        = "vrack-bandwidth-1000-24sys"
          public_bandwidth_option = "bandwidth-1000-24sys"
          private_ip              = "10.150.200.20"
        }
        gra = {
          datacenter              = "gra"
          plan_code               = "24sys022"
          storage_option          = "softraid-2x512nvme-24sys"
          ram_option              = "ram-32g-ecc-2133-24sys"
          bandwidth_option        = "vrack-bandwidth-1000-24sys"
          public_bandwidth_option = "bandwidth-1000-24sys"
          private_ip              = "10.150.200.21"
        }
        sbg = {
          datacenter              = "sbg"
          plan_code               = "24sys022"
          storage_option          = "softraid-2x512nvme-24sys"
          ram_option              = "ram-32g-ecc-2133-24sys"
          bandwidth_option        = "vrack-bandwidth-1000-24sys"
          public_bandwidth_option = "bandwidth-1000-24sys"
          private_ip              = "10.150.200.22"
        }
      }
      private_network_cidr = "10.150.200.0/24"
    }

    production = {
      controlplane_nodes = {
        rbx = {
          region      = "RBX-A"
          flavor_name = "b3-8"
          private_ip  = "10.150.100.10"
        }
        gra = {
          region      = "GRA9"
          flavor_name = "b3-8"
          private_ip  = "10.150.100.11"
        }
        par = {
          region      = "EU-WEST-PAR"
          flavor_name = "b3-8"
          private_ip  = "10.150.100.12"
        }
      }
      worker_nodes = {
        rbx = {
          datacenter       = "rbx"
          plan_code               = "25rise01"
          storage_option          = "softraid-3x1920nvme-25rise"
          ram_option              = "ram-64g-ecc-3200-25rise"
          bandwidth_option        = "vrack-bandwidth-1000-25rise"
          public_bandwidth_option = "bandwidth-1000-25rise"
          private_ip       = "10.150.100.20"
        }
        gra = {
          datacenter       = "gra"
          plan_code               = "25rise01"
          storage_option          = "softraid-3x1920nvme-25rise"
          ram_option              = "ram-64g-ecc-3200-25rise"
          bandwidth_option        = "vrack-bandwidth-1000-25rise"
          public_bandwidth_option = "bandwidth-1000-25rise"
          private_ip       = "10.150.100.21"
        }
        sbg = {
          datacenter       = "sbg"
          plan_code               = "25rise01"
          storage_option          = "softraid-3x1920nvme-25rise"
          ram_option              = "ram-64g-ecc-3200-25rise"
          bandwidth_option        = "vrack-bandwidth-1000-25rise"
          public_bandwidth_option = "bandwidth-1000-25rise"
          private_ip       = "10.150.100.22"
        }
      }
      private_network_cidr = "10.150.100.0/24"
    }

    development = {
      controlplane_nodes = {
        rbx = {
          region      = "RBX-A"
          flavor_name = "d2-8"
          private_ip  = "10.150.50.10"
        }
      }
      worker_nodes         = {}
      private_network_cidr = "10.150.50.0/24"
    }
  }

  topology = local.topology_by_env[local.env]
}

inputs = {
  controlplane_nodes   = local.topology.controlplane_nodes
  worker_nodes         = local.topology.worker_nodes
  private_network_cidr = local.topology.private_network_cidr
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "s3" {
    bucket = "${get_env("TF_VAR_tf_state_s3_bucket")}"
    key    = "yucca/o11y/v3/ovh/account/${local.env}${local.stage != "" ? "/${local.stage}" : ""}"
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
