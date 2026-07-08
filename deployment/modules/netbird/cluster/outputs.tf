# Plaintext setup key fed to the Talos netbird extension (NB_SETUP_KEY) by the
# talos/cluster module, which consumes this via a terragrunt dependency.
output "talos_setup_key" {
  sensitive = true
  value     = netbird_setup_key.talos.key
}

# Routing-peer setup key; consumed by kubernetes/helm -> netbird-setup-key Secret.
output "k8s_routing_peer_setup_key" {
  sensitive = true
  value     = netbird_setup_key.k8s_routing_peer.key
}
