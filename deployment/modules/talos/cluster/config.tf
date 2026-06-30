terraform {
  required_version = "~> 1.10"

  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0"
    }
    # Retained only so Terraform can destroy the (now config-removed) tailnet keys —
    # a provider must be present to delete its own resources. Drop with the provider +
    # vars in the follow-up once the keys are gone from state.
    tailscale = {
      source  = "tailscale/tailscale"
      version = "0.29.2"
    }
  }
}
