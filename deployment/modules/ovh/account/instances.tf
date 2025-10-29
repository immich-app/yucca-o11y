locals {
  availability_zones = [
    "eu-west-par-a",
    "eu-west-par-b",
    "eu-west-par-c"
  ]
}

resource "ovh_cloud_project_instance" "instances" {
  count          = 3
  name           = "instance-${count.index}"
  service_name   = ovh_cloud_project.yucca.project_id
  region         = "EU-WEST-PAR"
  billing_period = "hourly"

  boot_from {
    # Debian 13 for EU-WEST-PAR
    image_id = "17d31bc8-0c7d-4f20-a3ab-1d67c2669a61"
  }

  flavor {
    # B3-8 for EU-WEST-PAR
    flavor_id = "91fa3187-0f7d-489e-a75e-a7f6541482ee"
  }

  network {
    public = true
  }

  ssh_key {
    name = ovh_cloud_project_ssh_key.my_key.name
  }

  availability_zone = element(local.availability_zones, count.index % length(local.availability_zones))
}
