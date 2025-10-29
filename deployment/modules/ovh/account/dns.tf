resource "ovh_domain_zone" "zone" {
  plan {
    duration     = data.ovh_order_cart_product_plan.zone.selected_price.0.duration
    plan_code    = data.ovh_order_cart_product_plan.zone.plan_code
    pricing_mode = data.ovh_order_cart_product_plan.zone.selected_price.0.pricing_mode

    configuration {
      label = "zone"
      value = "yucca.immich.cc"
    }

    configuration {
      label = "template"
      value = "minimized"
    }
  }
}

resource "ovh_domain_zone_record" "instances" {
  for_each = { for combination in flatten([
    for instance in ovh_cloud_project_instance.instances: [
      for address in instance.addresses: {
        key = "${instance.name}-${address.ip}"
        instance = instance
        address = address
      }
    ]
  ]) : combination.key => combination }

  zone      = ovh_domain_zone.zone.name
  subdomain = "${each.value.instance.name}.srv"
  fieldtype = each.value.address.version == 4 ? "A" : "AAAA"
  ttl       = 3600
  target    = each.value.address.ip
}
