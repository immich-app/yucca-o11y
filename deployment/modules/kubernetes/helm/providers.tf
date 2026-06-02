# operator_endpoint is a static CP private IP (in the apiserver cert SANs),
# not the VIP — see talos/cluster/main.tf.
provider "helm" {
  kubernetes = {
    host                   = var.cluster.operator_endpoint
    client_certificate     = base64decode(var.cluster.client_certificate)
    client_key             = base64decode(var.cluster.client_key)
    cluster_ca_certificate = base64decode(var.cluster.ca_certificate)
  }
}

provider "kubernetes" {
  host                   = var.cluster.operator_endpoint
  client_certificate     = base64decode(var.cluster.client_certificate)
  client_key             = base64decode(var.cluster.client_key)
  cluster_ca_certificate = base64decode(var.cluster.ca_certificate)
}
