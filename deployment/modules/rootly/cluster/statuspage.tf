# Public status page served by Rootly, independent of the cluster it reports
# on. Hosts are plain CNAMEs under futostatus.com (the apex can't CNAME on OVH
# DNS, so it stays on the LB). Rootly TLS comes from Google Trust Services, so
# the zone CAA must allow pki.goog alongside letsencrypt.org.
locals {
  status_page_domain = var.env == "production" ? "status.futostatus.com" : "status.${var.env}.futostatus.com"
}

# Functionalities are the friendly public names shown as status-page items;
# the rfc1123 service names stay internal. Status flips when an incident marks
# the functionality affected — raw alerts alone don't.
resource "rootly_functionality" "grafana_heartbeat" {
  name               = "o11y / Grafana Heartbeat"
  public_description = "Dead man's switch for the o11y ${var.env} Grafana alerting pipeline."
  service_ids        = [rootly_service.o11y.id]
  environment_ids    = [rootly_environment.env.id]
}

resource "rootly_status_page" "o11y" {
  title                     = "o11y-${var.env}"
  public_title              = var.env == "production" ? "FUTO Status" : "FUTO Status (${var.env})"
  description               = "Public status page for the o11y ${var.env} stack."
  public                    = true
  enabled                   = true
  allow_search_engine_index = var.env == "production"
  external_domain_names     = [local.status_page_domain]
  functionality_ids         = [rootly_functionality.grafana_heartbeat.id]
  show_uptime               = true
  show_uptime_last_days     = 90
}
