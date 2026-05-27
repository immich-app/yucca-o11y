# Tailnet-global. Declares all envs in one document so applying for one env
# doesn't wipe another env's tags. autoApprovers pre-approves each env's CP
# subnet route so kubectl/talosctl over Tailscale works without manual
# approval.
resource "tailscale_acl" "this" {
  overwrite_existing_content = true

  acl = jsonencode({
    tagOwners = merge(
      {
        "tag:management"    = []
        "tag:project-yucca" = ["autogroup:admin"]
      },
      {
        for env in keys(var.subnet_routes_by_env) :
        "tag:env-${env}" => ["autogroup:admin"]
      },
    )

    autoApprovers = {
      routes = {
        for env, cidr in var.subnet_routes_by_env :
        cidr => ["tag:env-${env}"]
      }
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
  devices_approval_on                         = true
  devices_auto_updates_on                     = true
  devices_key_duration_days                   = 5
  users_approval_on                           = true
  users_role_allowed_to_join_external_tailnet = "member"
  https_enabled                               = true
}
