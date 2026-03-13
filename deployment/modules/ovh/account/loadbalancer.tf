# data "ovh_order_cart_product_plan" "iplb" {
#   cart_id        = data.ovh_order_cart.mycart.id
#   price_capacity = "renew"
#   product        = "ipLoadbalancing"
#   plan_code      = var.ovh_iplb_plan_code
# }

# resource "ovh_iploadbalancing" "this" {
#   ovh_subsidiary = data.ovh_me.account.ovh_subsidiary
#   display_name   = "o11y${local.resource_suffix}"

#   plan {
#     duration     = data.ovh_order_cart_product_plan.iplb.selected_price.0.duration
#     plan_code    = data.ovh_order_cart_product_plan.iplb.plan_code
#     pricing_mode = data.ovh_order_cart_product_plan.iplb.selected_price.0.pricing_mode

#     configuration {
#       label = "region"
#       value = "europe"
#     }
#   }
# }

# # --- HTTP Farm: vmauth-external backends (port 30427) ---

# resource "ovh_iploadbalancing_http_farm" "vmauth_external" {
#   service_name = ovh_iploadbalancing.this.service_name
#   display_name = "vmauth-external"
#   zone         = "all"
#   port         = 30427
#   balance      = "roundrobin"

#   probe {
#     type     = "http"
#     port     = 30427
#     interval = 30
#     url      = "/health"
#     method   = "GET"
#     match    = "status"
#     pattern  = "200"
#   }
# }

# resource "ovh_iploadbalancing_http_farm_server" "vmauth_external" {
#   for_each = ovh_dedicated_server.node

#   service_name = ovh_iploadbalancing.this.service_name
#   farm_id      = ovh_iploadbalancing_http_farm.vmauth_external.id
#   display_name = "o11y-${var.env}-${each.key}"
#   address      = each.value.ip
#   port         = 30427
#   status       = "active"
#   weight       = 1
# }

# resource "ovh_iploadbalancing_http_frontend" "vmauth" {
#   service_name    = ovh_iploadbalancing.this.service_name
#   display_name    = "vmauth"
#   zone            = "all"
#   port            = "8427"
#   default_farm_id = ovh_iploadbalancing_http_farm.vmauth_external.id
# }

# resource "ovh_iploadbalancing_refresh" "this" {
#   service_name = ovh_iploadbalancing.this.service_name
#   keepers = [
#     ovh_iploadbalancing_http_farm.vmauth_external.id,
#     ovh_iploadbalancing_http_frontend.vmauth.id,
#     join(",", [for k, v in ovh_iploadbalancing_http_farm_server.vmauth_external : v.id]),
#   ]
# }
