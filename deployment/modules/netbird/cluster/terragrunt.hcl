include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "."

  extra_arguments custom_vars {
    commands = get_terraform_commands_that_need_vars()
  }
}

# Per-env: the route advertises this env's vRack CIDR, sourced from the ovh module.
dependency "ovh" {
  config_path = "../../ovh/account"

  mock_outputs = {
    private_network_cidr = "10.150.200.0/24"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  private_network_cidr = dependency.ovh.outputs.private_network_cidr
}
