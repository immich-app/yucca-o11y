# OVH IP Load Balancing (IPLB) — the standalone managed LB. It owns a public IP
# and balances TCP :443 to the workers' Envoy NodePort (30443); TLS passes
# through and terminates at Envoy.
#
# Backends are reached over the workers' PUBLIC IPs, not the vRack: this lb1
# order came back vrackEligibility=false (OVH does not grant vRack on new IPLB
# orders here), so the vRack attach is structurally unavailable. The public-IP
# path is sound — each worker replies from its OWN public IP (not a foreign
# Additional IP), so OVH per-NIC anti-spoofing doesn't drop it (the bug that
# made MetalLB unworkable). The only cost is that 30443 must be open on the
# workers' public NIC (Envoy is TLS-only; see talos/cluster/workers.tf).
data "ovh_order_cart_product_plan" "iplb" {
  cart_id        = data.ovh_order_cart.mycart.id
  price_capacity = "renew"
  product        = "ipLoadbalancing"
  plan_code      = var.loadbalancer_plan_code
}

data "ovh_order_cart_product_options_plan" "iplb_zone" {
  cart_id           = data.ovh_order_cart_product_plan.iplb.cart_id
  price_capacity    = data.ovh_order_cart_product_plan.iplb.price_capacity
  product           = data.ovh_order_cart_product_plan.iplb.product
  plan_code         = data.ovh_order_cart_product_plan.iplb.plan_code
  options_plan_code = "iplb-zone-lb1-${var.loadbalancer_zone}"
}

resource "ovh_iploadbalancing" "envoy" {
  ovh_subsidiary = data.ovh_order_cart.mycart.ovh_subsidiary
  display_name   = "o11y-${var.env}-envoy"

  plan {
    duration     = data.ovh_order_cart_product_plan.iplb.selected_price[0].duration
    plan_code    = data.ovh_order_cart_product_plan.iplb.plan_code
    pricing_mode = data.ovh_order_cart_product_plan.iplb.selected_price[0].pricing_mode
  }

  plan_option {
    duration     = data.ovh_order_cart_product_options_plan.iplb_zone.selected_price[0].duration
    plan_code    = data.ovh_order_cart_product_options_plan.iplb_zone.plan_code
    pricing_mode = data.ovh_order_cart_product_options_plan.iplb_zone.selected_price[0].pricing_mode
  }
}

resource "ovh_iploadbalancing_tcp_farm" "envoy" {
  service_name = ovh_iploadbalancing.envoy.service_name
  display_name = "o11y-${var.env}-envoy"
  port         = 443
  zone         = tolist(ovh_iploadbalancing.envoy.zone)[0]
  balance      = "roundrobin"

  probe {
    type     = "tcp"
    port     = var.envoy_node_port
    interval = 30
  }
}

resource "ovh_iploadbalancing_tcp_farm_server" "envoy" {
  for_each = var.worker_nodes

  service_name = ovh_iploadbalancing.envoy.service_name
  farm_id      = ovh_iploadbalancing_tcp_farm.envoy.id
  display_name = "o11y-${var.env}-worker-${each.key}"
  # Worker public IP — the LB can't ride the vRack (see header), so it reaches
  # the NodePort over the public NIC. The reply is sourced from this same IP,
  # which is legitimate, so anti-spoofing passes.
  address = ovh_dedicated_server.worker[each.key].ip
  port    = var.envoy_node_port
  status  = "active"
  # Prepend a PROXY protocol v2 header so Envoy sees the real client IP instead
  # of the LB's outbound IP. Envoy's ClientTrafficPolicy enables proxyProtocol
  # with optional=true (kubernetes/apps/base/envoy-proxy/clienttrafficpolicy.yaml)
  # so the bare-TCP health probe still passes.
  proxy_protocol_version = "v2"
  probe                  = true
}

resource "ovh_iploadbalancing_tcp_frontend" "envoy" {
  service_name    = ovh_iploadbalancing.envoy.service_name
  display_name    = "o11y-${var.env}-envoy"
  zone            = tolist(ovh_iploadbalancing.envoy.zone)[0]
  port            = "443"
  default_farm_id = ovh_iploadbalancing_tcp_farm.envoy.id
}

# Push the farm/frontend config to the running LB whenever it changes.
resource "ovh_iploadbalancing_refresh" "envoy" {
  service_name = ovh_iploadbalancing.envoy.service_name

  keepers = [
    ovh_iploadbalancing_tcp_frontend.envoy.id,
    join(",", [for s in ovh_iploadbalancing_tcp_farm_server.envoy : s.id]),
  ]
}
