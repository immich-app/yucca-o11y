provider "grafana" {
  url  = local.grafana_url
  auth = "${var.grafana_admin_user}:${data.onepassword_item.grafana_admin_password.password}"
}

provider "onepassword" {
  connect_url   = var.op_connect_host
  connect_token = var.op_connect_token_write
}
