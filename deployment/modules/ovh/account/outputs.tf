output "controlplane_nodes" {
  value = {
    for k, v in ovh_cloud_project_instance.controlplane : k => {
      name       = v.name
      region     = var.controlplane_nodes[k].region
      public_ip  = one([for a in v.addresses : a.ip if a.version == 4 && a.ip != var.controlplane_nodes[k].private_ip])
      private_ip = var.controlplane_nodes[k].private_ip
    }
  }
}

output "worker_nodes" {
  value = {
    for k, v in ovh_dedicated_server.worker : k => {
      name       = v.display_name
      datacenter = var.worker_nodes[k].datacenter
      public_ip  = v.ip
      private_ip = var.worker_nodes[k].private_ip
    }
  }
}

output "loadbalancer_ip" {
  value = ovh_iploadbalancing.envoy.ipv4
}

# bare_metal for workers, public_cloud for CPs — sharing breaks upgrade on
# the other. Openstack URL is hand-built because the talos provider's
# data source returns null for platform = "openstack".
output "talos_installer_images" {
  value = {
    bare_metal   = data.talos_image_factory_urls.metal.urls.installer
    public_cloud = "factory.talos.dev/openstack-installer/${var.talos_schematic_id}:${var.talos_version}"
  }
}

output "private_network_cidr" {
  value = var.private_network_cidr
}
