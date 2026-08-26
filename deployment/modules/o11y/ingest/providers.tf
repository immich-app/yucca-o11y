provider "onepassword" {
  connect_url   = var.op_connect_host
  connect_token = var.op_connect_token_write
}
