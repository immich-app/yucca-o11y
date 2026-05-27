# Zones are registered out-of-band; this module only manages records on them.
locals {
  domains            = ["futostat.us", "futostatus.com"]
  wildcard_subdomain = var.env == "staging" ? "*.staging" : "*"

  envoy_ip_gateway = trimsuffix(ovh_vrack_ip.envoy.gateway, "/32")

  # /30 has two host addresses; OVH holds one as the vRack gateway, the other
  # is the customer-usable IP that MetalLB advertises.
  envoy_ip = [
    for offset in [1, 2] :
    cidrhost(ovh_ip_service.envoy.ip, offset)
    if cidrhost(ovh_ip_service.envoy.ip, offset) != local.envoy_ip_gateway
  ][0]
}

resource "ovh_domain_zone_record" "lb" {
  for_each = toset(local.domains)

  zone      = each.value
  subdomain = var.env == "staging" ? "staging" : ""
  fieldtype = "A"
  ttl       = 3600
  target    = local.envoy_ip
}

resource "ovh_domain_zone_record" "wildcard" {
  for_each = toset(local.domains)

  zone      = each.value
  subdomain = local.wildcard_subdomain
  fieldtype = "CNAME"
  ttl       = 3600
  target    = var.env == "staging" ? "staging.${each.value}." : "${each.value}."
}
