provider "netbird" {
  # PAT from the shared_tf vault (Netbird Cloud). management_url defaults to
  # https://api.netbird.io, so it is left unset.
  token = var.netbird_tf_pat
}
