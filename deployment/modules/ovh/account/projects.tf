data "ovh_order_cart_product_plan" "cloud_project" {
  cart_id        = data.ovh_order_cart.mycart.id
  price_capacity = "renew"
  product        = "cloud"
  plan_code      = "project.2018"
}

resource "ovh_cloud_project" "this" {
  ovh_subsidiary = data.ovh_me.account.ovh_subsidiary
  description    = "o11y-${var.env}"

  plan {
    duration     = data.ovh_order_cart_product_plan.cloud_project.selected_price.0.duration
    plan_code    = data.ovh_order_cart_product_plan.cloud_project.plan_code
    pricing_mode = data.ovh_order_cart_product_plan.cloud_project.selected_price.0.pricing_mode
  }
}
