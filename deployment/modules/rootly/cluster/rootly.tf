data "rootly_alert_urgency" "high" {
  name = "High"
}

resource "rootly_environment" "env" {
  name        = var.env
  description = "o11y ${var.env} cluster"
}

resource "rootly_service" "o11y" {
  name            = "o11y-${var.env}"
  description     = "Central observability stack (${var.env}): VictoriaMetrics/VictoriaLogs ingestion and Grafana alerting."
  environment_ids = [rootly_environment.env.id]
}

# Dead man's switch for the Grafana alerting pipeline. Grafana pings this from
# an always-firing rule; if pings stop (Grafana, its DB, the cluster, or the
# notification pipeline is down) Rootly raises the alert through its own path.
resource "rootly_heartbeat" "grafana_alerting" {
  name                     = "o11y-${var.env}-grafana-alerting"
  description              = "Expires when the o11y ${var.env} Grafana alerting pipeline stops pinging."
  interval                 = 5
  interval_unit            = "minutes"
  alert_summary            = "o11y ${var.env} Grafana alerting heartbeat missed; the alert pipeline may be down."
  alert_urgency_id         = data.rootly_alert_urgency.high.id
  notification_target_type = "Service"
  notification_target_id   = rootly_service.o11y.id
  enabled                  = true
}

# Deliver Rootly alerts for this service to the env's Discord channel. Interim
# receiver until escalation policies exist; Rootly cloud -> Discord, independent
# of the cluster whose death the heartbeat reports.
resource "rootly_workflow_alert" "discord_fired" {
  name        = "o11y-${var.env}-alert-fired-to-discord"
  description = "Posts new alerts on the o11y-${var.env} service to the ${var.env} Discord channel."
  enabled     = true
  service_ids = [rootly_service.o11y.id]
  trigger_params {
    triggers = ["alert_created"]
  }
}

resource "rootly_workflow_task_http_client" "discord_fired" {
  workflow_id = rootly_workflow_alert.discord_fired.id
  name        = "Post to Discord"
  task_params {
    url     = data.onepassword_item.discord_webhook.password
    method  = "POST"
    headers = jsonencode({ "Content-Type" = "application/json" })
    body = jsonencode({
      username   = "Rootly"
      avatar_url = "https://avatars.githubusercontent.com/u/78240982"
      content    = "🔴 **Rootly** (o11y-${var.env}): {{ alert.summary }}"
    })
    succeed_on_status = "200|204"
    retry_count       = "4"
    retry_wait_time   = "15"
  }
}

resource "rootly_workflow_alert" "discord_resolved" {
  name        = "o11y-${var.env}-alert-resolved-to-discord"
  description = "Posts alert resolutions on the o11y-${var.env} service to the ${var.env} Discord channel."
  enabled     = true
  service_ids = [rootly_service.o11y.id]
  trigger_params {
    triggers               = ["alert_status_updated"]
    alert_condition_status = "IS"
    alert_statuses         = ["resolved"]
  }
}

resource "rootly_workflow_task_http_client" "discord_resolved" {
  workflow_id = rootly_workflow_alert.discord_resolved.id
  name        = "Post to Discord"
  task_params {
    url     = data.onepassword_item.discord_webhook.password
    method  = "POST"
    headers = jsonencode({ "Content-Type" = "application/json" })
    body = jsonencode({
      username   = "Rootly"
      avatar_url = "https://avatars.githubusercontent.com/u/78240982"
      content    = "🟢 **Rootly** (o11y-${var.env}): resolved — {{ alert.summary }}"
    })
    succeed_on_status = "200|204"
    retry_count       = "4"
    retry_wait_time   = "15"
  }
}
