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
