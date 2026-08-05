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
