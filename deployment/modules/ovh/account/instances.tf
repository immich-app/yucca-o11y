# resource "ovh_dedicated_server" "instance" {
#   provider = ovh.soyoustart
#   ovh_subsidiary = data.ovh_me.account.ovh_subsidiary
#   display_name = "Server"
#   plan = [
#     {
#       plan_code = "25sysle023"
#       duration = "P1M"
#       pricing_mode = "default"
#
#       configuration = [
#         {
#           label = "dedicated_datacenter"
#           value = "fra"
#         },
#         {
#           label = "dedicated_os"
#           value = "none_64.en"
#         },
#         {
#           label = "region"
#           value = "europe"
#         }
#       ]
#     }
#   ]
#
#   plan_option = [
#     {
#       duration = "P1M"
#       plan_code = "bandwidth-500-unguaranteed-25sysle"
#       pricing_mode = "default"
#       quantity = 1
#     },
#     {
#       duration = "P1M"
#       plan_code = "ram-32g-ecc-2666-25sysle022"
#       pricing_mode = "default"
#       quantity = 1
#     },
#     {
#       duration = "P1M"
#       plan_code = "softraid-2x960nvme-25sysle022"
#       pricing_mode = "default"
#       quantity = 1
#     },
#     {
#       duration = "P1M"
#       plan_code = "vrack-bandwidth-500-25sysle"
#       pricing_mode = "default"
#       quantity = 1
#     }
#   ]
#   customizations = {
#     image_url = "https://factory.talos.dev/image/4dd8e3a8b6203d3c14f049da8db4d3bb0d6d3e70c5e89dfcc1e709e81914f63c/v1.11.5/metal-amd64.qcow2"
#     image_type = "qcow2"
#   }
# }

resource "ovh_dedicated_server" "kimsufi" {
  ovh_subsidiary = data.ovh_me.account.ovh_subsidiary
  # range = "eco"
  display_name = "Kimsufi Test Server"
  service_name = "ns3047483.ip-164-132-171.eu"
  plan = [
    {
      plan_code = "24sys012"
      duration = "P1M"
      pricing_mode = "default"

      configuration = [
        {
          label = "dedicated_datacenter"
          value = "rbx"
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
      duration = "P1M"
      plan_code = "softraid-2x512nvme-24sys"
      pricing_mode = "default"
      quantity = 1
    },
    {
      duration = "P1M"
      plan_code = "vrack-bandwidth-500-24sys"
      pricing_mode = "default"
      quantity = 1
    },
    {
      duration = "P1M"
      plan_code = "bandwidth-1000-24sys"
      pricing_mode = "default"
      quantity = 1
    },
    {
      duration = "P1M"
      plan_code = "ram-32g-ecc-2666-24sys"
      pricing_mode = "default"
      quantity = 1
    }
  ]
  efi_bootloader_path = "\\EFI\\BOOT\\BOOTX64.EFI"
  os = "byoi_64"
  customizations = {
    efi_bootloader_path = "\\EFI\\BOOT\\BOOTX64.EFI"
    image_url = "https://factory.talos.dev/image/4a0d65c669d46663f377e7161e50cfd570c401f26fd9e7bda34a0216b6f1922b/v1.12.1/metal-amd64.qcow2"
    image_type = "qcow2"
  }
}

resource "ovh_dedicated_server" "kimsufi2" {
  ovh_subsidiary = data.ovh_me.account.ovh_subsidiary
  # range = "eco"
  display_name = "Kimsufi Test Server 2"
  plan = [
    {
      plan_code = "24sys012"
      duration = "P1M"
      pricing_mode = "default"

      configuration = [
        {
          label = "dedicated_datacenter"
          value = "lon"
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
      duration = "P1M"
      plan_code = "softraid-2x512nvme-24sys"
      pricing_mode = "default"
      quantity = 1
    },
    {
      duration = "P1M"
      plan_code = "vrack-bandwidth-500-24sys"
      pricing_mode = "default"
      quantity = 1
    },
    {
      duration = "P1M"
      plan_code = "bandwidth-1000-24sys"
      pricing_mode = "default"
      quantity = 1
    },
    {
      duration = "P1M"
      plan_code = "ram-32g-ecc-2666-24sys"
      pricing_mode = "default"
      quantity = 1
    }
  ]
  efi_bootloader_path = "\\EFI\\BOOT\\BOOTX64.EFI"
  os = "byoi_64"

  customizations = {
    efi_bootloader_path = "\\EFI\\BOOT\\BOOTX64.EFI"
    image_url = "https://factory.talos.dev/image/4a0d65c669d46663f377e7161e50cfd570c401f26fd9e7bda34a0216b6f1922b/v1.12.1/metal-amd64.qcow2"
    image_type = "qcow2"
  }
}

data "ovh_order_cart_product_plan" "vrack" {
  cart_id        = data.ovh_order_cart.mycart.id
  price_capacity = "renew"
  product        = "vrack"
  plan_code      = "vrack"
}

resource "ovh_vrack" "vrack" {
  ovh_subsidiary = data.ovh_order_cart.mycart.ovh_subsidiary
  name           = "o11y"
  description    = "O11Y vRack"

  plan {
    duration     = data.ovh_order_cart_product_plan.vrack.selected_price.0.duration
    plan_code    = data.ovh_order_cart_product_plan.vrack.plan_code
    pricing_mode = data.ovh_order_cart_product_plan.vrack.selected_price.0.pricing_mode
  }
}

data "ovh_dedicated_server" "this" {
  service_name = ovh_dedicated_server.kimsufi2.service_name
}

resource "ovh_vrack_dedicated_server_interface" "vdsi" {
  service_name = ovh_vrack.vrack.service_name #name of the vrack
  interface_id = data.ovh_dedicated_server.this.enabled_vrack_vnis[0]
}

data "ovh_dedicated_server" "kimsufi" {
  service_name = ovh_dedicated_server.kimsufi.service_name
}

output "test2" {
  value = data.ovh_dedicated_server.kimsufi
}

output "test3" {
  value = data.ovh_dedicated_server.this
}

# resource "ovh_vrack_dedicated_server_interface" "vdsi2" {
#   service_name = ovh_vrack.vrack.service_name #name of the vrack
#   interface_id = data.ovh_dedicated_server.kimsufi.enabled_vrack_vnis[0]
# }

