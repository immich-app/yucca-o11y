output "flux_operator_status" {
  value = helm_release.flux_operator.status
}

output "flux_instance_status" {
  value = helm_release.flux_instance.status
}
