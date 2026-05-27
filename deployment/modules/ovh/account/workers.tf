resource "ovh_dedicated_server" "worker" {
  for_each = var.worker_nodes

  ovh_subsidiary = data.ovh_me.account.ovh_subsidiary
  range          = "eco"
  display_name   = "o11y-${var.env}-worker-${each.key}"

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
      plan_code    = each.value.bandwidth_option
      pricing_mode = "default"
      quantity     = 1
    },
    {
      duration     = "P1M"
      plan_code    = each.value.public_bandwidth_option
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
    image_url           = replace(data.talos_image_factory_urls.metal.urls.iso, ".iso", ".raw")
    image_type          = "raw"
  }

  lifecycle {
    # customizations are consumed only at order time; Talos upgrades go via
    # machine.install.image. Re-ordering would re-charge the install fee.
    ignore_changes = [customizations]
  }
}
