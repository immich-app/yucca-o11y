# Publish the public ingest endpoints into the shared vault.
#
# The bearer token that guards these lives beside them as
# O11Y_VICTORIAMETRICS_VMAUTH_PASSWORD, created elsewhere because it is a
# generated credential. These are not generated — they are this cluster's own
# addresses — so they are declared here, where the gateway they point at is
# defined.
#
# The point is single ownership rather than confidentiality: the hostnames are
# public. If the gateway moves, it moves once and every consumer that reads the
# vault follows, instead of each repo carrying a copy to be found and edited.
#
# The shared vault, not the env vault, because the readers are other projects:
# yucca's own components reach VictoriaMetrics in-cluster and never need these.
locals {
  env_short = var.env == "production" ? "prod" : var.env == "development" ? "dev" : var.env

  # Mirrors the gateway hostnames in docs/05-shipping-metrics-guide.md.
  vmauth_host = local.env_short == "prod" ? "vmauth.${var.app_domain}" : "vmauth.${local.env_short}.${var.app_domain}"
}

data "onepassword_vault" "shared" {
  name = "shared_tf_${local.env_short}"
}

# Prometheus remote-write. What vmagent and anything else speaking the protocol
# should post to; vmauth routes /insert/0/.* to vminsert.
resource "onepassword_item" "victoriametrics_remote_write_url" {
  vault    = data.onepassword_vault.shared.uuid
  title    = "O11Y_VICTORIAMETRICS_REMOTE_WRITE_URL"
  category = "password"
  password = "https://${local.vmauth_host}/insert/0/prometheus/api/v1/write"
}

# Prometheus exposition import, on the same vminsert route.
#
# For pushers that cannot produce remote-write: it is protobuf wrapped in
# snappy, which means shipping an encoder and a compressor. A Cloudflare Worker
# is the case in hand — fmeet.futo.org posts client and server telemetry through
# one — and for anything already running vmagent the remote-write URL above is
# still the right answer.
resource "onepassword_item" "victoriametrics_import_url" {
  vault    = data.onepassword_vault.shared.uuid
  title    = "O11Y_VICTORIAMETRICS_IMPORT_URL"
  category = "password"
  password = "https://${local.vmauth_host}/insert/0/prometheus/api/v1/import/prometheus"
}

# VictoriaLogs, JSON lines. The path carries no account segment, unlike the
# metrics routes above — see the VMUser targetRefs in
# kubernetes/apps/base/victoria-metrics-users/app/vmuser-remote-clusters.yaml,
# which is what vmauth will actually accept.
resource "onepassword_item" "victorialogs_jsonline_url" {
  vault    = data.onepassword_vault.shared.uuid
  title    = "O11Y_VICTORIALOGS_JSONLINE_URL"
  category = "password"
  password = "https://${local.vmauth_host}/insert/jsonline"
}
