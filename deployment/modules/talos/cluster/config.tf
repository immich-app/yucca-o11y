terraform {
  required_version = "~> 1.10"

  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.10.1"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = "0.28.0"
    }
  }
}
