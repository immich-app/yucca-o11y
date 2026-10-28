include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "."

  extra_arguments custom_vars {
    commands = get_terraform_commands_that_need_vars()

    # The onepassword provider treats OP_SERVICE_ACCOUNT_TOKEN as a configured
    # credential alongside the explicit Connect creds and errors on the conflict.
    # CI sets it for `op run` itself; blank it for the tofu child process only.
    env_vars = {
      OP_SERVICE_ACCOUNT_TOKEN = ""
    }
  }
}

# storage.tf finds the env's project with a data source rather than reading
# ovh/account's outputs, so this edge is what orders `run --all`: after
# ovh/account on apply, before it on destroy.
dependencies {
  paths = ["../../ovh/account"]
}
