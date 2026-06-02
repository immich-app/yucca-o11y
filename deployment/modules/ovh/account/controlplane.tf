resource "ovh_cloud_project_instance" "controlplane" {
  for_each = var.controlplane_nodes

  service_name   = ovh_cloud_project.this.project_id
  region         = each.value.region
  billing_period = "hourly" # b3-8 doesn't support monthly billing
  name           = "o11y-${var.env}-cp-${each.key}"

  boot_from {
    image_id = one([
      for img in data.ovh_cloud_project_images.talos[each.key].images :
      img.id if img.name == var.talos_public_cloud_image_name
    ])
  }

  flavor {
    flavor_id = one([
      for f in data.ovh_cloud_project_flavors.cp[each.key].flavors :
      f.id
    ])
  }

  ssh_key {
    name = ovh_cloud_project_ssh_key.my_key.name
  }

  network {
    public = true
    private {
      ip = each.value.private_ip
      network {
        # Per-region OpenStack UUID; the composite `.id` isn't accepted here.
        id        = ovh_cloud_project_network_private.cluster.regions_openstack_ids[each.value.region]
        subnet_id = ovh_cloud_project_network_private_subnet_v2.cluster[each.key].id
      }
    }
  }

  lifecycle {
    # boot_from is consumed at create only; Talos upgrades go via machine.install.image.
    ignore_changes = [boot_from]
  }
}
