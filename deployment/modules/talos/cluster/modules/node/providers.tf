terraform {
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = ">= 0.10"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = ">= 0.28"
    }
  }
}
