provider "helm" {
  alias    = "cluster"
  for_each = var.clusters

  kubernetes = {
    host                   = each.value.endpoint
    client_certificate     = base64decode(each.value.client_certificate)
    client_key             = base64decode(each.value.client_key)
    cluster_ca_certificate = base64decode(each.value.ca_certificate)
  }
}

provider "kubernetes" {
  alias    = "cluster"
  for_each = var.clusters

  host                   = each.value.endpoint
  client_certificate     = base64decode(each.value.client_certificate)
  client_key             = base64decode(each.value.client_key)
  cluster_ca_certificate = base64decode(each.value.ca_certificate)
}
