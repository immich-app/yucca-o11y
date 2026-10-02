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

# Alert delivery, routed by team into Zulip through its Slack-compatible
# incoming webhook (Zulip has no Rootly integration of its own). Harbor has
# its own channel; every other project shares yucca-alerts. The topic is
# <project>-<env>, so each project and env threads apart within the
# channel. Bodies are Slack mrkdwn, which Zulip rewrites to its own markdown.
locals {
  zulip_channels = {
    for project in local.projects :
    project => project == "harbor" ? "harbor-alerts" : "yucca-alerts"
  }

  zulip_webhook_urls = {
    for project, channel in local.zulip_channels :
    project => "${var.rootly_zulip_webhook}&stream=${urlencode(channel)}&topic=${urlencode("${project}-${var.env}")}"
  }
}

resource "rootly_workflow_alert" "zulip_fired" {
  for_each    = local.zulip_channels
  name        = "${each.key}-${var.env}-alert-fired-to-zulip"
  description = "Posts new alerts on the ${each.key} ${var.env} service to the ${each.value} Zulip channel."
  enabled     = true
  service_ids = [local.project_service_ids[each.key]]
  trigger_params {
    triggers = ["alert_created"]
  }
}

resource "rootly_workflow_task_http_client" "zulip_fired" {
  for_each    = local.zulip_channels
  workflow_id = rootly_workflow_alert.zulip_fired[each.key].id
  name        = "Post to Zulip"
  task_params {
    url     = local.zulip_webhook_urls[each.key]
    method  = "POST"
    headers = jsonencode({ "Content-Type" = "application/json" })
    body = jsonencode({
      text = "🔴 *Rootly* (${var.env}): <{{ alert.url }}|{{ alert.summary }}>"
    })
    succeed_on_status = "200"
    retry_count       = "4"
    retry_wait_time   = "15"
  }
}

resource "rootly_workflow_alert" "zulip_resolved" {
  for_each    = local.zulip_channels
  name        = "${each.key}-${var.env}-alert-resolved-to-zulip"
  description = "Posts alert resolutions on the ${each.key} ${var.env} service to the ${each.value} Zulip channel."
  enabled     = true
  service_ids = [local.project_service_ids[each.key]]
  trigger_params {
    triggers               = ["alert_status_updated"]
    alert_condition_status = "IS"
    alert_statuses         = ["resolved"]
  }
}

resource "rootly_workflow_task_http_client" "zulip_resolved" {
  for_each    = local.zulip_channels
  workflow_id = rootly_workflow_alert.zulip_resolved[each.key].id
  name        = "Post to Zulip"
  task_params {
    url     = local.zulip_webhook_urls[each.key]
    method  = "POST"
    headers = jsonencode({ "Content-Type" = "application/json" })
    body = jsonencode({
      text = "🟢 *Rootly* (${var.env}): resolved <{{ alert.url }}|{{ alert.summary }}>"
    })
    succeed_on_status = "200"
    retry_count       = "4"
    retry_wait_time   = "15"
  }
}
