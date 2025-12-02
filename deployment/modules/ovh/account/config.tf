terraform {
  required_version = "~> 1.10"

  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "~> 2"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.8.1"
    }
    tailscale = {
      source = "tailscale/tailscale"
      version = "0.24.0"
    }
  }
}
