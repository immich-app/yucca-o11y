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
#
resource "ovh_dedicated_server" "instance" {
  ovh_subsidiary = data.ovh_me.account.ovh_subsidiary
  display_name = "RISE Test Server"
  service_name = "ns33238000.ip-213-32-25.eu"
  plan = [
    {
      plan_code = "25rises0112"
      duration = "P1M"
      pricing_mode = "default"

      configuration = [
        {
          label = "dedicated_datacenter"
          value = "gra"
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
      plan_code = "bandwidth-1000-24rise"
      pricing_mode = "default"
      quantity = 1
    },
    {
      duration = "P1M"
      plan_code = "ram-64g-rise-s"
      pricing_mode = "default"
      quantity = 1
    },
    {
      duration = "P1M"
      plan_code = "softraid-2x512nvme-24rise"
      pricing_mode = "default"
      quantity = 1
    }
  ]
  efi_bootloader_path = "/boot/efi/boot/bootx64.efi"
  os = "byolinux_64"
  customizations = {
    image_url = "https://factory.talos.dev/image/4dd8e3a8b6203d3c14f049da8db4d3bb0d6d3e70c5e89dfcc1e709e81914f63c/v1.11.4/metal-amd64.qcow2"
  }
}
