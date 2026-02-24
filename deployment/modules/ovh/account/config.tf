terraform {
  required_version = "~> 1.10"

  required_providers {
    ovh = {
      source  = "terraform.local/local/ovh"
      version = "0.0.1"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.10.1"
    }
  }
}
