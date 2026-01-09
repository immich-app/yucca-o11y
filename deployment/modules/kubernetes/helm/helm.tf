output "test" {
  value = data.terraform_remote_state.talos_state.outputs.installer_image
}

//data.terraform_remote_state.api_keys_state.outputs.terraform_key_cloudflare_account


resource "helm_release" "flux_operator" {
  name  = "flux-operator"
  namespace = "flux-system"
  repository = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart = "flux-operator"
  version = "0.37.1"
  create_namespace = true
  cleanup_on_fail = true
  wait_for_jobs = true
}

resource "helm_release" "flux_instance" {
  name  = "flux-instance"
  namespace = "flux-system"
  repository = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart = "flux-instance"
  version = "0.37.1"
  values = [file("${path.module}/values.yml")]
  cleanup_on_fail = true
  wait_for_jobs = true
  depends_on = [helm_release.flux_operator]
}

/*
---

helmDefaults:
  cleanupOnFail: true
  wait: true
  waitForJobs: true

releases:
  - name: flux-operator
    namespace: flux-system
    chart: oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator
    version: 0.37.1
    values: ['../kubernetes/apps/flux-system/flux-operator/app/values.yaml']

  - name: flux-instance
    namespace: flux-system
    chart: oci://ghcr.io/controlplaneio-fluxcd/charts/flux-instance
    version: 0.37.1
    values: ['../kubernetes/apps/flux-system/flux-instance/app/values.yaml']
    needs: ['flux-system/flux-operator']
 */
