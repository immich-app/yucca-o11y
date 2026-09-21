output "status_page_cname_records" {
  value = rootly_status_page.o11y.cname_records
}

output "heartbeat_ping_url" {
  value = rootly_heartbeat.grafana_alerting.ping_url
}

output "heartbeat_secret" {
  value     = rootly_heartbeat.grafana_alerting.secret
  sensitive = true
}

output "grafana_alert_sources" {
  value = { for project, source in rootly_alerts_source.grafana : project => source.id }
}

output "project_service_ids" {
  value = local.project_service_ids
}
