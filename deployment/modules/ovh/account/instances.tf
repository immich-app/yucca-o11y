moved {
  from = ovh_dedicated_server.kimsufi2
  to = ovh_dedicated_server.node["lon"]
}

moved {
  from = ovh_dedicated_server.kimsufi
  to = ovh_dedicated_server.node["rbx"]
}

resource "ovh_dedicated_server" "node" {
  for_each = var.nodes

  ovh_subsidiary = data.ovh_me.account.ovh_subsidiary
  range          = "eco"
  display_name   = "o11y-${var.env}-${each.key}"

  plan = [
    {
      plan_code    = each.value.plan_code
      duration     = "P1M"
      pricing_mode = "default"

      configuration = [
        {
          label = "dedicated_datacenter"
          value = each.value.datacenter
        },
        {
          label = "dedicated_os"
          value = "none_64.en"
        },
        {
          label = "region"
          value = "europe"
        }
      ]
    }
  ]

  plan_option = [
    {
      duration     = "P1M"
      plan_code    = each.value.storage_option
      pricing_mode = "default"
      quantity     = 1
    },
    {
      duration     = "P1M"
      plan_code    = "vrack-bandwidth-500-24sys"
      pricing_mode = "default"
      quantity     = 1
    },
    {
      duration     = "P1M"
      plan_code    = "bandwidth-1000-24sys"
      pricing_mode = "default"
      quantity     = 1
    },
    {
      duration     = "P1M"
      plan_code    = each.value.ram_option
      pricing_mode = "default"
      quantity     = 1
    }
  ]

  efi_bootloader_path = "\\EFI\\BOOT\\BOOTX64.EFI"
  os                  = "byoi_64"

  customizations = {
    efi_bootloader_path = "\\EFI\\BOOT\\BOOTX64.EFI"
    image_url           = replace(data.talos_image_factory_urls.this.urls.iso, ".iso", ".qcow2")
    image_type          = "qcow2"
  }
}

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

data "ovh_dedicated_server" "nodes" {
  for_each     = ovh_dedicated_server.node
  service_name = each.value.service_name
}

resource "ovh_vrack_dedicated_server_interface" "nodes" {
  for_each = {
    for k, v in var.nodes : k => v
    if v.has_vrack
  }
  service_name = ovh_vrack.this.service_name
  interface_id = data.ovh_dedicated_server.nodes[each.key].enabled_vrack_vnis[0]
}

data "talos_image_factory_urls" "this" {
  talos_version = var.talos_version
  schematic_id  = var.talos_schematic_id
  platform      = "metal"
}
