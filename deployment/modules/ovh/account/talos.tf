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
        install = {
          disk = "/dev/nvme0n1"
        }
      }
      cluster = {
        allowSchedulingOnControlPlanes = true
      }
    }),
    <<EOT
      apiVersion: v1alpha1
      kind: HostnameConfig
      hostname: o11y
      auto: off
    EOT
    ,
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
    ,
    <<EOT
      apiVersion: v1alpha1
      kind: LinkConfig
      name: eno1
      up: true
    EOT
    ,
    <<EOT
      apiVersion: v1alpha1
      kind: LinkConfig
      name: eno2
      up: true
    EOT
    ,
    <<EOT
      apiVersion: v1alpha1
      kind: VLANConfig
      name: eno2.2600
      vlanID: 2600
      vlanMode: 802.1q
      parent: eno2
      up: true
      addresses:
        - address: 10.150.200.10/16
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
  talos_version = "v1.12.1"
  schematic_id  = "4a0d65c669d46663f377e7161e50cfd570c401f26fd9e7bda34a0216b6f1922b"
  platform      = "metal"
}

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node = ovh_dedicated_server.kimsufi2.ip
}

output "installer_image" {
  value = data.talos_image_factory_urls.this.urls.installer
}

output "kubernetes_client_configuration" {
  value = talos_cluster_kubeconfig.this.kubernetes_client_configuration
  sensitive = true
}

