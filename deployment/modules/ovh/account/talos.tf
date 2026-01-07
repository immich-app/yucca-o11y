resource "talos_machine_secrets" "this" {}

data "talos_machine_configuration" "this" {
  cluster_name     = "example-cluster"
  machine_type     = "controlplane"
  cluster_endpoint = "https://o11y:6443"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
}

data "talos_client_configuration" "this" {
  cluster_name         = "example-cluster"
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = [ovh_dedicated_server.kimsufi2.ip]
}

data "talos_machine_disks" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = ovh_dedicated_server.kimsufi2.ip
  selector             = "disk.transport == 'nvme'"
}

output "test" {
  value = data.talos_machine_disks.this.disks[0].dev_path
}

resource "talos_machine_configuration_apply" "this" {
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this.machine_configuration
  node                        = ovh_dedicated_server.kimsufi2.ip
  config_patches = [
    yamlencode({
      machine = {
        network = {
          hostname = "o11y"
        }
        install = {
          disk = "/dev/nvme0n1"
        }
      }
      cluster = {
        allowSchedulingOnControlPlanes = true
      }
    }),
    <<EOT
      name: tailscale
      apiVersion: v1alpha1
      kind: ExtensionServiceConfig
      environment:
      - TS_AUTHKEY=${tailscale_tailnet_key.test.key}
    EOT
    ,
    <<EOT
      apiVersion: v1alpha1
      kind: VolumeConfig
      name: EPHEMERAL
      provisioning:
        diskSelector:
          match: system_disk
        minSize: 50GB
        maxSize: 50GB
        grow: false
    EOT
    ,
    <<EOT
      apiVersion: v1alpha1
      kind: UserVolumeConfig
      name: hostpath
      provisioning:
        diskSelector:
          match: system_disk
        minSize: 20GB
        grow: true
    EOT
  ]
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [
    talos_machine_configuration_apply.this
  ]
  node                 = ovh_dedicated_server.kimsufi2.ip
  client_configuration = talos_machine_secrets.this.client_configuration
}

data "talos_image_factory_urls" "this" {
  talos_version = "v1.11.5"
  schematic_id  = "4a0d65c669d46663f377e7161e50cfd570c401f26fd9e7bda34a0216b6f1922b"
  platform      = "metal"
}

output "installer_image" {
  value = data.talos_image_factory_urls.this.urls.installer
}
