resource "kubernetes_config_map_v1" "vm_zone_endpoints" {
  depends_on = [helm_release.flux_operator]

  metadata {
    name      = "vm-zone-endpoints"
    namespace = "flux-system"
  }

  data = {
    ZONE_2_NODE_IP = var.other_node_ips[0]
    ZONE_3_NODE_IP = var.other_node_ips[1]
  }
}

resource "kubernetes_secret_v1" "vmauth_external_credentials" {
  depends_on = [helm_release.flux_instance]

  metadata {
    name      = "vmauth-external-credentials"
    namespace = "o11y"
  }

  data = {
    "reader-password" = var.vmauth_external_reader_password
    "writer-password" = var.vmauth_external_writer_password
  }
}

resource "kubernetes_secret_v1" "vmauth_internal_credentials" {
  depends_on = [helm_release.flux_instance]

  metadata {
    name      = "vmauth-internal-credentials"
    namespace = "o11y"
  }

  data = {
    "reader-password" = var.vmauth_internal_reader_password
    "writer-password" = var.vmauth_internal_writer_password
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
