terraform {
  required_version = "~> 1.10"

  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = "0.29.2"
    }
  }
}
