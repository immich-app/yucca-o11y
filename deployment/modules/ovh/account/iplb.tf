# OVH IP Load Balancing (IPLB) — the standalone managed LB. Unlike the Public
# Cloud Octavia LB, it takes backends by arbitrary IP (so the bare-metal workers
# work directly) and attaches to the vRack, owning a public IP and the return
# path. TLS terminates at Envoy (TCP passthrough on 443 -> worker NodePort 30443).
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

# Attach the LB to the vRack and give it a NAT range in the cluster subnet so it
# can reach the worker vRack IPs.
resource "ovh_vrack_iploadbalancing" "envoy" {
  service_name     = ovh_vrack.this.service_name
  ip_loadbalancing = ovh_iploadbalancing.envoy.service_name
}

resource "ovh_iploadbalancing_vrack_network" "envoy" {
  service_name = ovh_vrack_iploadbalancing.envoy.ip_loadbalancing
  subnet       = var.private_network_cidr
  vlan         = 0
  nat_ip       = var.loadbalancer_nat_cidr
  display_name = "o11y-${var.env}"
}

resource "ovh_iploadbalancing_tcp_farm" "envoy" {
  service_name     = ovh_iploadbalancing.envoy.service_name
  display_name     = "o11y-${var.env}-envoy"
  port             = 443
  zone             = tolist(ovh_iploadbalancing.envoy.zone)[0]
  vrack_network_id = ovh_iploadbalancing_vrack_network.envoy.vrack_network_id
  balance          = "roundrobin"

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
  address      = each.value.private_ip
  port         = var.envoy_node_port
  status       = "active"
  # PROXY protocol (for real client IPs) is a follow-up — it needs a matching
  # Envoy ClientTrafficPolicy, or connections break.
  probe = true
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
