terraform {
  required_version = "~> 1.10"

  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "2.22.0"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 3.3"
    }
  }
}
