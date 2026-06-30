# Plaintext setup key fed to the Talos netbird extension (NB_SETUP_KEY) by the
# talos/cluster module, which consumes this via a terragrunt dependency.
output "talos_setup_key" {
  sensitive = true
  value     = netbird_setup_key.talos.key
}
