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
# Fired posts and reminders carry the alert description under the title line;
# Rootly substitutes it as raw text, so the whole message goes through to_json
# to keep its newlines and quotes from breaking the JSON body.
# Rootly ignores service_ids on alert workflows, so each one matches the
# alert's notification target instead: the service its alert source posts
# to, which Rootly records in the payload.
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
    triggers                = ["alert_created"]
    alert_condition_payload = "IS"
    alert_query_payload     = "$.rootly.notification_target.id"
    alert_payload           = [local.project_service_ids[each.key]]
  }
}

resource "rootly_workflow_task_http_client" "zulip_fired" {
  for_each    = local.zulip_channels
  workflow_id = rootly_workflow_alert.zulip_fired[each.key].id
  name        = "Post to Zulip"
  task_params {
    url               = local.zulip_webhook_urls[each.key]
    method            = "POST"
    headers           = jsonencode({ "Content-Type" = "application/json" })
    body              = <<-EOT
      {% capture text %}🔴 *Rootly* (${var.env}): <{{ alert.url }}|{{ alert.summary }}>
      {{ alert.description }}{% endcapture %}{"text": {{ text | to_json }}}
    EOT
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
    triggers                = ["alert_status_updated"]
    alert_condition_status  = "IS"
    alert_statuses          = ["resolved"]
    alert_condition_payload = "IS"
    alert_query_payload     = "$.rootly.notification_target.id"
    alert_payload           = [local.project_service_ids[each.key]]
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

# Stopgap until escalation policies page someone: a high-urgency alert that is
# still open and unacknowledged a day after it fired gets a daily reminder in
# its topic. Rootly re-checks the conditions before every run, so reminders
# stop once the alert is acknowledged or resolved.
resource "rootly_workflow_alert" "zulip_reminder" {
  for_each              = local.zulip_channels
  name                  = "${each.key}-${var.env}-alert-reminder-to-zulip"
  description           = "Reminds the ${each.value} Zulip channel daily about high-urgency ${each.key} ${var.env} alerts that are still open and unacknowledged."
  enabled               = true
  service_ids           = [local.project_service_ids[each.key]]
  wait                  = "1 day"
  repeat_every_duration = "1 day"
  trigger_params {
    triggers                = ["alert_created"]
    alert_condition_status  = "IS"
    alert_statuses          = ["open", "triggered"]
    alert_condition_urgency = "IS"
    alert_urgency_ids       = [data.rootly_alert_urgency.high.id]
    alert_condition_payload = "IS"
    alert_query_payload     = "$.rootly.notification_target.id"
    alert_payload           = [local.project_service_ids[each.key]]
  }
}

resource "rootly_workflow_task_http_client" "zulip_reminder" {
  for_each    = local.zulip_channels
  workflow_id = rootly_workflow_alert.zulip_reminder[each.key].id
  name        = "Post to Zulip"
  task_params {
    url               = local.zulip_webhook_urls[each.key]
    method            = "POST"
    headers           = jsonencode({ "Content-Type" = "application/json" })
    body              = <<-EOT
      {% capture text %}⏰ *Rootly* (${var.env}): still open and unacknowledged <{{ alert.url }}|{{ alert.summary }}>
      {{ alert.description }}{% endcapture %}{"text": {{ text | to_json }}}
    EOT
    succeed_on_status = "200"
    retry_count       = "4"
    retry_wait_time   = "15"
  }
}
