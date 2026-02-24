terraform {
  required_version = "~> 1.10"

  required_providers {
    tailscale = {
      source  = "tailscale/tailscale"
      version = "0.28.0"
    }
  }
}
