terraform {
  required_version = "~> 1.10"

  required_providers {
    # FUTO-maintained fork (github.com/futo-org/terraform-provider-netbird), like yucca.
    # Only published to the Terraform registry, so the source is fully qualified —
    # OpenTofu would otherwise look it up on registry.opentofu.org.
    netbird = {
      source  = "registry.terraform.io/futo-org/netbird"
      version = "1.0.2" # fixes group TF->API resources decode (rename of groups with tagged resources)
    }
  }
}
