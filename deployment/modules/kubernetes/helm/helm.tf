resource "helm_release" "flux_operator" {
  name             = "flux-operator"
  namespace        = "flux-system"
  repository       = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart            = "flux-operator"
  version          = var.flux_operator_version
  create_namespace = true
  cleanup_on_fail  = true
  wait_for_jobs    = true
  depends_on       = [helm_release.coredns]
}

resource "helm_release" "flux_instance" {
  name            = "flux-instance"
  namespace       = "flux-system"
  repository      = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart           = "flux-instance"
  version         = var.flux_operator_version
  values          = [templatefile("${path.module}/values.yaml", { env = var.env })]
  cleanup_on_fail = true
  wait_for_jobs   = true
  depends_on      = [helm_release.flux_operator]
}
