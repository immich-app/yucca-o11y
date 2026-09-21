# Grafana alert delivery. One Rootly alert source per Grafana folder (project),
# each with its own secret so Rootly can tell the projects apart, and one
# service per project so alerts can later get their own escalation policy and
# status-page items. The o11y folder reuses the service the heartbeat targets.
#
# Grafana posts each grouped notification to the source's /notify/Service/<id>
# endpoint with the source secret as a query parameter; the notification title
# becomes the alert summary, commonLabels become alert labels, and a resolved
# notification resolves the alert.
locals {
  projects = toset(["o11y", "yucca", "fmeet", "harbor", "fip"])

  project_service_ids = merge(
    { o11y = rootly_service.o11y.id },
    { for project, service in rootly_service.project : project => service.id },
  )

  grafana_webhooks_base = "https://webhooks.rootly.com/webhooks/incoming/grafana_webhooks"
}

data "rootly_alert_urgency" "medium" {
  name = "Medium"
}

data "rootly_alert_urgency" "low" {
  name = "Low"
}

resource "rootly_service" "project" {
  for_each        = setsubtract(local.projects, ["o11y"])
  name            = "${each.key}-${var.env}"
  description     = "${each.key} (${var.env}): alerts raised by the o11y Grafana from the ${each.key} folder."
  environment_ids = [rootly_environment.env.id]
}

# Urgency follows the rule's severity label (critical -> High, warning ->
# Medium); anything unlabelled lands on Low.
resource "rootly_alerts_source" "grafana" {
  for_each         = local.projects
  name             = "${each.key}-${var.env}-grafana"
  source_type      = "grafana"
  alert_urgency_id = data.rootly_alert_urgency.low.id

  alert_source_urgency_rules_attributes {
    kind             = "payload"
    json_path        = "$.commonLabels.severity"
    operator         = "is"
    value            = "critical"
    alert_urgency_id = data.rootly_alert_urgency.high.id
  }

  alert_source_urgency_rules_attributes {
    kind             = "payload"
    json_path        = "$.commonLabels.severity"
    operator         = "is"
    value            = "warning"
    alert_urgency_id = data.rootly_alert_urgency.medium.id
  }
}
