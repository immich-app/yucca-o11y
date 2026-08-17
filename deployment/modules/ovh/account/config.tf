terraform {
  required_version = "~> 1.10"

  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "2.19.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0"
    }
  }
}
