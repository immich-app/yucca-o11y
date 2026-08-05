# Zones are registered out-of-band; this module only manages records on them.
locals {
  domains            = ["futostat.us", "futostatus.com"]
  wildcard_subdomain = var.env == "staging" ? "*.staging" : "*"

  # Rootly status page host for this env; the specific CNAME overrides the
  # wildcard for that one name. The target only exists in the rootly module's
  # state after a post-create refresh, hence the null guard.
  status_page_subdomain = var.env == "production" ? "status" : "status.${var.env}"
  status_page_cname     = lookup(var.status_page_cname_records, "${local.status_page_subdomain}.futostatus.com", null)
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
  fieldtype = "A"
  ttl       = 3600
  target    = ovh_iploadbalancing.envoy.ipv4
}

resource "ovh_domain_zone_record" "status_page" {
  count = local.status_page_cname != null ? 1 : 0

  zone      = "futostatus.com"
  subdomain = local.status_page_subdomain
  fieldtype = "CNAME"
  ttl       = 3600
  target    = "${local.status_page_cname}."
}

# Once any CAA record exists, every CA not listed is refused: letsencrypt.org
# keeps cert-manager renewals working for both clusters' certs on this zone,
# pki.goog (Google Trust Services) lets Rootly provision the status-page certs.
# Zone-wide records belong to the production pass, like the apex A above.
resource "ovh_domain_zone_record" "caa" {
  for_each = var.env == "production" ? {
    letsencrypt = "0 issue \"letsencrypt.org\""
    rootly      = "0 issue \"pki.goog; cansignhttpexchanges=yes\""
  } : {}

  zone      = "futostatus.com"
  subdomain = ""
  fieldtype = "CAA"
  ttl       = 3600
  target    = each.value
}
