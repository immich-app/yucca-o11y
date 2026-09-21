output "grafana_url" {
  value = local.grafana_url
}

output "rootly_service_account_id" {
  value = grafana_service_account.rootly.id
}

output "rootly_service_account_token" {
  value     = grafana_service_account_token.rootly.key
  sensitive = true
}
