terraform {
  required_version = "~> 1.10"

  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "~> 2"
    }
  }
}
