resource "ovh_domain_name" "futostat_us" {
  domain_name = "futostat.us"
}

resource "ovh_domain_name" "futostatus_com" {
  domain_name = "futostatus.com"
}

locals {
  domains = [
    ovh_domain_name.futostat_us.domain_name,
    ovh_domain_name.futostatus_com.domain_name,
  ]

  # Wildcard subdomain: staging → *.staging, prod → *
  wildcard_subdomain = var.env == "staging" ? "*.staging" : "*"

  # Per-node A records for direct node access
  node_dns_records = flatten([
    for domain in local.domains : [
      for key, node in var.nodes : [
        {
          key       = "${domain}-${key}-public"
          zone      = domain
          subdomain = "o11y-${var.env}-${key}"
          target    = ovh_dedicated_server.node[key].ip
        },
        {
          key       = "${domain}-${key}-internal"
          zone      = domain
          subdomain = "o11y-${var.env}-${key}.internal"
          target    = node.vlan_ip
        },
      ]
    ]
  ])
}

# Per-node A records (direct node access)
resource "ovh_domain_zone_record" "nodes" {
  for_each = { for record in local.node_dns_records : record.key => record }

  zone      = each.value.zone
  subdomain = each.value.subdomain
  fieldtype = "A"
  ttl       = 3600
  target    = each.value.target
}

resource "ovh_domain_zone_record" "lb" {
  for_each = toset(local.domains)

  zone      = each.value
  subdomain = var.env == "staging" ? "staging" : ""
  fieldtype = "A"
  ttl       = 3600
  target    = ovh_iploadbalancing.this.ipv4
}

# Wildcard CNAMEs: *.staging.futostat.us → staging.futostat.us (staging)
#                  *.futostat.us → futostat.us (production)
resource "ovh_domain_zone_record" "wildcard" {
  for_each = toset(local.domains)

  zone      = each.value
  subdomain = local.wildcard_subdomain
  fieldtype = "CNAME"
  ttl       = 3600
  target    = var.env == "staging" ? "staging.${each.value}." : "${each.value}."
}
