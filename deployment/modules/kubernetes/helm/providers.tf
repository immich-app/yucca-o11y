provider "helm" {
  debug = true
  kubernetes = {
    host     = "https://o11y:6443"

    client_certificate     = base64decode(data.terraform_remote_state.talos_state.outputs.kubernetes_client_configuration.client_certificate)
    client_key             = base64decode(data.terraform_remote_state.talos_state.outputs.kubernetes_client_configuration.client_key)
    cluster_ca_certificate = base64decode(data.terraform_remote_state.talos_state.outputs.kubernetes_client_configuration.ca_certificate)
  }
}
