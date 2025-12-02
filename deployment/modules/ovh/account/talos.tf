resource "talos_machine_secrets" "this" {}

data "talos_machine_configuration" "this" {
  cluster_name     = "example-cluster"
  machine_type     = "controlplane"
  cluster_endpoint = "https://tf-test:6443"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
}

data "talos_client_configuration" "this" {
  cluster_name         = "example-cluster"
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = ["51.89.228.250"]
}

resource "talos_machine_configuration_apply" "this" {
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this.machine_configuration
  node                        = "51.89.228.250"
  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk = "/dev/vda"
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
        minSize: 10GB
        maxSize: 10GB
        grow: false
    EOT
    # ,
    # <<EOT
    #   apiVersion: v1alpha1
    #   kind: RawVolumeConfig
    #   name: openebs
    #   provisioning:
    #     diskSelector:
    #       match: system_disk
    #     minSize: 20GB
    #     grow: true
    # EOT
  ]
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [
    talos_machine_configuration_apply.this
  ]
  node                 = "51.89.228.250"
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
