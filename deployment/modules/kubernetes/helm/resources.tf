# Consumed via postBuild.substituteFrom in kubernetes/apps/base/metallb-config.
resource "kubernetes_config_map_v1" "metallb_pool" {
  depends_on = [helm_release.flux_operator]

  metadata {
    name      = "metallb-pool"
    namespace = "flux-system"
  }

  data = {
    ENVOY_IP       = var.envoy_ip
    ENVOY_IP_BLOCK = var.envoy_ip_block
  }
}

resource "kubernetes_namespace_v1" "cert_manager" {
  depends_on = [helm_release.flux_operator]

  metadata {
    annotations = {
      "kustomize.toolkit.fluxcd.io/prune" = "disabled"
    }
    labels = {
      "kustomize.toolkit.fluxcd.io/name"      = "cluster-apps"
      "kustomize.toolkit.fluxcd.io/namespace" = "flux-system"
    }
    name = "cert-manager"
  }
}

resource "kubernetes_secret_v1" "ovh_credentials" {
  depends_on = [kubernetes_namespace_v1.cert_manager]

  metadata {
    name      = "ovh-credentials"
    namespace = "cert-manager"
  }

  data = {
    applicationKey         = var.ovh_application_key
    applicationSecret      = var.ovh_application_secret
    applicationConsumerKey = var.ovh_consumer_key
  }
}

resource "kubernetes_namespace_v1" "external_secrets" {
  depends_on = [helm_release.flux_operator]

  metadata {
    annotations = {
      "kustomize.toolkit.fluxcd.io/prune" = "disabled"
    }
    labels = {
      "kustomize.toolkit.fluxcd.io/name"      = "cluster-apps"
      "kustomize.toolkit.fluxcd.io/namespace" = "flux-system"
    }
    name = "external-secrets"
  }
}

resource "kubernetes_secret_v1" "onepassword_connect_credentials" {
  depends_on = [kubernetes_namespace_v1.external_secrets]

  metadata {
    name      = "onepassword-connect-credentials"
    namespace = "external-secrets"
  }

  data = {
    "1password-credentials.json" = var.op_credentials_file
  }
}

resource "kubernetes_secret_v1" "onepassword_connect_token" {
  depends_on = [kubernetes_namespace_v1.external_secrets]

  metadata {
    name      = "onepassword-connect"
    namespace = "external-secrets"
  }

  data = {
    token = var.op_connect_token
  }
}

resource "kubernetes_secret_v1" "onepassword_connect_environment" {
  depends_on = [kubernetes_namespace_v1.external_secrets]

  metadata {
    name      = "onepassword-connect-environment"
    namespace = "external-secrets"
  }

  data = {
    token = var.op_connect_token_env
  }
}
