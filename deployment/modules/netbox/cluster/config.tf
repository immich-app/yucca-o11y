terraform {
  required_version = "~> 1.10"

  required_providers {
    netbox = {
      source  = "e-breuninger/netbox"
      version = "~> 5.0"
    }
  }
}
