resource "ovh_cloud_project_ssh_key" "my_key" {
  service_name = ovh_cloud_project.yucca.project_id

  name       = "my_key"
  public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG3/TlFlL/byLbM5aCt5QptpYSQCJIYFxKtjEtkAD5KI my-key"
}
