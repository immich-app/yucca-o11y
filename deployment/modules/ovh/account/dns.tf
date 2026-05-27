# Zones are registered out-of-band; this module only manages records on them.
locals {
  domains            = ["futostat.us", "futostatus.com"]
  wildcard_subdomain = var.env == "staging" ? "*.staging" : "*"
}

resource "ovh_domain_zone_record" "lb" {
  for_each = toset(local.domains)

  zone      = each.value
  subdomain = var.env == "staging" ? "staging" : ""
  fieldtype = "A"
  ttl       = 3600
  target    = ovh_iploadbalancing.envoy.ipv4
}

resource "ovh_domain_zone_record" "wildcard" {
  for_each = toset(local.domains)

  zone      = each.value
  subdomain = local.wildcard_subdomain
  fieldtype = "CNAME"
  ttl       = 3600
  target    = var.env == "staging" ? "staging.${each.value}." : "${each.value}."
}
