data "ovh_order_cart_product_plan" "additional_ip" {
  cart_id        = data.ovh_order_cart.mycart.id
  price_capacity = "renew"
  product        = "ip"
  plan_code      = var.additional_ip_plan_code
}

resource "ovh_ip_service" "envoy" {
  ovh_subsidiary = data.ovh_order_cart.mycart.ovh_subsidiary
  description    = "o11y-${var.env}-envoy"

  plan {
    duration     = data.ovh_order_cart_product_plan.additional_ip.selected_price.0.duration
    plan_code    = data.ovh_order_cart_product_plan.additional_ip.plan_code
    pricing_mode = data.ovh_order_cart_product_plan.additional_ip.selected_price.0.pricing_mode

    configuration {
      label = "country"
      value = "FR"
    }
  }
}

resource "ovh_vrack_ip" "envoy" {
  service_name = ovh_vrack.this.service_name
  block        = ovh_ip_service.envoy.ip
}
