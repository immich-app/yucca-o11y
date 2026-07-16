# Exactly what downstream providers (kubernetes/helm) need to reach the cluster.
output "cluster" {
  sensitive = true
  value = {
    operator_endpoint  = local.operator_endpoint
    client_certificate = talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_certificate
    client_key         = talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_key
    ca_certificate     = talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate
  }
}

output "talos_client_configuration" {
  sensitive = true
  value     = data.talos_client_configuration.this.talos_config
}

# TF-authored kubeconfig with two contexts: the HA mesh endpoint (default) and a
# direct-CP break-glass for bootstrap/DR before the gateway exists
# (kubectl --context <cluster>-direct). Both endpoints are apiserver cert SANs.
output "kubeconfig" {
  sensitive = true
  value = yamlencode({
    apiVersion        = "v1"
    kind              = "Config"
    "current-context" = local.cluster_name
    clusters = [
      {
        name = local.cluster_name
        cluster = {
          server                       = "https://kube.${var.mesh_dns_zone}:6443"
          "certificate-authority-data" = talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate
        }
      },
      {
        name = "${local.cluster_name}-direct"
        cluster = {
          server                       = local.operator_endpoint
          "certificate-authority-data" = talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate
        }
      },
    ]
    users = [
      {
        name = "admin@${local.cluster_name}"
        user = {
          "client-certificate-data" = talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_certificate
          "client-key-data"         = talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_key
        }
      },
    ]
    contexts = [
      {
        name    = local.cluster_name
        context = { cluster = local.cluster_name, user = "admin@${local.cluster_name}" }
      },
      {
        name    = "${local.cluster_name}-direct"
        context = { cluster = "${local.cluster_name}-direct", user = "admin@${local.cluster_name}" }
      },
    ]
  })
}
