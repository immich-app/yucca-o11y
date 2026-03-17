data "ovh_order_cart_product_plan" "iplb" {
  cart_id        = data.ovh_order_cart.mycart.id
  price_capacity = "renew"
  product        = "ipLoadbalancing"
  plan_code      = var.ovh_iplb_plan_code
}

resource "ovh_iploadbalancing" "this" {
  ovh_subsidiary = data.ovh_me.account.ovh_subsidiary
  display_name   = "o11y${local.resource_suffix}"

  plan {
    duration     = data.ovh_order_cart_product_plan.iplb.selected_price.0.duration
    plan_code    = data.ovh_order_cart_product_plan.iplb.plan_code
    pricing_mode = data.ovh_order_cart_product_plan.iplb.selected_price.0.pricing_mode

    configuration {
      label = "region"
      value = "europe"
    }
  }
}

resource "ovh_iploadbalancing_tcp_farm" "envoy" {
  service_name = ovh_iploadbalancing.this.service_name
  display_name = "envoy-proxy"
  zone         = "all"
  port         = 30443
  balance      = "roundrobin"

  probe {
    type     = "tcp"
    port     = 30443
    interval = 30
  }
}

resource "ovh_iploadbalancing_tcp_farm_server" "envoy" {
  for_each = ovh_dedicated_server.node

  service_name = ovh_iploadbalancing.this.service_name
  farm_id      = ovh_iploadbalancing_tcp_farm.envoy.id
  display_name = "o11y-${var.env}-${each.key}"
  address      = each.value.ip
  port         = 30443
  status       = "active"
  weight       = 1
}

resource "ovh_iploadbalancing_tcp_frontend" "https" {
  service_name    = ovh_iploadbalancing.this.service_name
  display_name    = "https"
  zone            = "all"
  port            = "443"
  default_farm_id = ovh_iploadbalancing_tcp_farm.envoy.id
}

resource "ovh_iploadbalancing_refresh" "this" {
  service_name = ovh_iploadbalancing.this.service_name
  keepers = [
    ovh_iploadbalancing_tcp_farm.envoy.id,
    ovh_iploadbalancing_tcp_frontend.https.id,
    join(",", [for k, v in ovh_iploadbalancing_tcp_farm_server.envoy : v.id]),
  ]
}
