data "ovh_order_cart_product_plan" "vrack" {
  cart_id        = data.ovh_order_cart.mycart.id
  price_capacity = "renew"
  product        = "vrack"
  plan_code      = "vrack"
}

resource "ovh_vrack" "this" {
  ovh_subsidiary = data.ovh_order_cart.mycart.ovh_subsidiary
  name           = "${var.vrack_name}-${var.env}"
  description    = "O11Y vRack - ${var.env}"

  plan {
    duration     = data.ovh_order_cart_product_plan.vrack.selected_price.0.duration
    plan_code    = data.ovh_order_cart_product_plan.vrack.plan_code
    pricing_mode = data.ovh_order_cart_product_plan.vrack.selected_price.0.pricing_mode
  }
}

resource "ovh_vrack_cloudproject" "this" {
  service_name = ovh_vrack.this.service_name
  project_id   = ovh_cloud_project.this.project_id
}

# Iterate the resource map (not var.worker_nodes) so -target=one-DC applies
# work — keys are still statically derivable through the worker for_each.
data "ovh_dedicated_server" "workers" {
  for_each     = ovh_dedicated_server.worker
  service_name = each.value.service_name
}

resource "ovh_vrack_dedicated_server_interface" "workers" {
  for_each = ovh_dedicated_server.worker

  service_name = ovh_vrack.this.service_name
  interface_id = data.ovh_dedicated_server.workers[each.key].enabled_vrack_vnis[0]
}
