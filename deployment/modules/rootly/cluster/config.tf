terraform {
  required_version = "~> 1.10"

  required_providers {
    rootly = {
      source  = "rootlyhq/rootly"
      version = "~> 5.17"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 3.3"
    }
  }
}
