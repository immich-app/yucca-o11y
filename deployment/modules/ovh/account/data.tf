data "ovh_me" "account" {
}

data "ovh_order_cart" "mycart" {
  ovh_subsidiary = data.ovh_me.account.ovh_subsidiary
}

data "talos_image_factory_urls" "metal" {
  talos_version = var.talos_version
  schematic_id  = var.talos_schematic_id
  platform      = "metal"
}

# The OpenStack installer URL is built manually in outputs.tf — the talos
# provider's data source returns null for platform = "openstack".

# Image must be pre-uploaded via `mise run talos:ul` before apply; the OVH
# provider doesn't upload custom images.
data "ovh_cloud_project_images" "talos" {
  for_each = var.controlplane_nodes

  service_name = ovh_cloud_project.this.project_id
  region       = each.value.region
  os_type      = "linux"
}

data "ovh_cloud_project_flavors" "cp" {
  for_each = var.controlplane_nodes

  service_name = ovh_cloud_project.this.project_id
  region       = each.value.region
  name_filter  = each.value.flavor_name
}
