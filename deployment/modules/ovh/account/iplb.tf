# OVH IP Load Balancing (IPLB) — the standalone managed LB. It owns a public IP
# and balances TCP :443 to the workers' Envoy NodePort (30443); TLS passes
# through and terminates at Envoy.
#
# Backends are reached over the workers' PUBLIC IPs, not the vRack: the lb1 offer
# is vrack:false (vRack needs lb2/dedicated at ~10x the cost — see the ADR). The
# public-IP path is sound — each worker replies from its OWN public IP, so OVH
# per-NIC anti-spoofing doesn't drop it. 30443 is firewalled to the IPLB NAT
# range 10.108.0.0/14 (talos/cluster/workers.tf), so the LB is the only ingress.
#
# Multi-zone: var.loadbalancer_zones drives one anycast LB IP announced from each
# zone, with a farm + frontend per zone (each farm reaches all workers). Staging
# runs a single zone (["gra"]); production runs several (e.g. ["gra","rbx","sbg"])
# for ingress HA. Each extra zone is a billable addon (~£16/mo at lb1).

locals {
  # One farm-server per (zone, worker) — every zone's farm can reach every worker.
  iplb_farm_servers = merge([
    for z in var.loadbalancer_zones : {
      for wk in keys(var.worker_nodes) : "${z}/${wk}" => { zone = z, worker = wk }
    }
  ]...)
}

data "ovh_order_cart_product_plan" "iplb" {
  cart_id        = data.ovh_order_cart.mycart.id
  price_capacity = "renew"
  product        = "ipLoadbalancing"
  plan_code      = var.loadbalancer_plan_code
}

# One zone addon per zone.
data "ovh_order_cart_product_options_plan" "iplb_zone" {
  for_each = toset(var.loadbalancer_zones)

  cart_id           = data.ovh_order_cart_product_plan.iplb.cart_id
  price_capacity    = data.ovh_order_cart_product_plan.iplb.price_capacity
  product           = data.ovh_order_cart_product_plan.iplb.product
  plan_code         = data.ovh_order_cart_product_plan.iplb.plan_code
  options_plan_code = "iplb-zone-lb1-${each.value}"
}

resource "ovh_iploadbalancing" "envoy" {
  ovh_subsidiary = data.ovh_order_cart.mycart.ovh_subsidiary
  display_name   = "o11y-${var.env}-envoy"

  plan {
    duration     = data.ovh_order_cart_product_plan.iplb.selected_price[0].duration
    plan_code    = data.ovh_order_cart_product_plan.iplb.plan_code
    pricing_mode = data.ovh_order_cart_product_plan.iplb.selected_price[0].pricing_mode
  }

  # One plan_option per subscribed zone (set at order time).
  dynamic "plan_option" {
    for_each = data.ovh_order_cart_product_options_plan.iplb_zone
    content {
      duration     = plan_option.value.selected_price[0].duration
      plan_code    = plan_option.value.plan_code
      pricing_mode = plan_option.value.selected_price[0].pricing_mode
    }
  }

  lifecycle {
    # plan_option (the zone set) is ForceNew — changing it recreates the LB and
    # its public IP. Zones are fixed at order time; ignore drift so a zone-list
    # edit can't silently destroy a live LB. To change zones, recreate the LB
    # deliberately (new IP → DNS update) or order the zone addon out-of-band.
    ignore_changes = [plan_option]
  }
}

# A farm per zone. Anycast routes a client to the nearest zone's frontend, which
# load-balances across all workers via that zone's farm.
resource "ovh_iploadbalancing_tcp_farm" "envoy" {
  for_each = toset(var.loadbalancer_zones)

  service_name = ovh_iploadbalancing.envoy.service_name
  display_name = "o11y-${var.env}-envoy"
  port         = 443
  zone         = each.value
  balance      = "roundrobin"

  probe {
    type     = "tcp"
    port     = var.envoy_node_port
    interval = 30
  }
}

resource "ovh_iploadbalancing_tcp_farm_server" "envoy" {
  for_each = local.iplb_farm_servers

  service_name = ovh_iploadbalancing.envoy.service_name
  farm_id      = ovh_iploadbalancing_tcp_farm.envoy[each.value.zone].id
  display_name = "o11y-${var.env}-worker-${each.value.worker}"
  # Worker public IP — the LB reaches the NodePort over the public NIC (see
  # header). The reply is sourced from this same IP, so anti-spoofing passes.
  address = ovh_dedicated_server.worker[each.value.worker].ip
  port    = var.envoy_node_port
  status  = "active"
  # PROXY protocol v2 so Envoy sees the real client IP. Envoy's ClientTrafficPolicy
  # enables proxyProtocol optional=true so the bare-TCP health probe still passes.
  proxy_protocol_version = "v2"
  probe                  = true
}

resource "ovh_iploadbalancing_tcp_frontend" "envoy" {
  for_each = toset(var.loadbalancer_zones)

  service_name    = ovh_iploadbalancing.envoy.service_name
  display_name    = "o11y-${var.env}-envoy"
  zone            = each.value
  port            = "443"
  default_farm_id = ovh_iploadbalancing_tcp_farm.envoy[each.value].id
}

# Push the farm/frontend config to the running LB whenever it changes. sort()
# keeps the keeper order-independent (it hashes the server set, not the map-key
# order). OVH stages farm/server edits as pending until a refresh runs, and
# in-place edits (e.g. proxy_protocol_version) keep the same ID, so the keeper
# hashes full server config rather than just IDs.
resource "ovh_iploadbalancing_refresh" "envoy" {
  service_name = ovh_iploadbalancing.envoy.service_name

  keepers = [
    join(",", sort([for f in ovh_iploadbalancing_tcp_frontend.envoy : f.id])),
    join(",", sort([for s in ovh_iploadbalancing_tcp_farm_server.envoy :
      "${s.id}:${s.address}:${s.port}:${s.proxy_protocol_version}:${s.status}"
    ])),
  ]
}
