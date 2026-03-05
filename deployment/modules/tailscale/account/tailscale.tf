resource "tailscale_acl" "this" {
  overwrite_existing_content = true

  acl = jsonencode({
    tagOwners = {
      "tag:management"       = []
      "tag:project-yucca"    = ["autogroup:admin"]
      "tag:env-${var.env}"   = ["autogroup:admin"]
    }
    grants = [
      {
        src = ["*"]
        dst = ["*"]
        ip  = ["*"]
      }
    ]
    ssh = [
      {
        action = "check"
        src    = ["autogroup:member"]
        dst    = ["autogroup:self"]
        users  = ["autogroup:nonroot", "root"]
      },
      {
        action = "accept"
        src    = ["autogroup:admin"]
        dst    = ["tag:management"]
        users  = ["autogroup:nonroot"]
      }
    ]
  })
}

resource "tailscale_tailnet_settings" "org" {
  # acls_externally_managed_on                  = true
  # acls_external_link                          = "https://github.com/octocat/Hello-World"
  devices_approval_on                         = true
  devices_auto_updates_on                     = true
  devices_key_duration_days                   = 5
  users_approval_on                           = true
  users_role_allowed_to_join_external_tailnet = "member"
  https_enabled                               = true
}
