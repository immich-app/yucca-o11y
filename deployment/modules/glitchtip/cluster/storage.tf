# GlitchTip's upload storage (sourcemaps, debug files), read by every replica.
# Same split as the backup buckets: a bucket owner ignores its user policy, so
# the bucket belongs to a keyless owner user and GlitchTip writes as a second
# user whose policy reaches this bucket only, not the backups in the project.
data "ovh_cloud_projects" "all" {}

locals {
  # ovh/account describes each env's public cloud project as o11y-<env>; this
  # data source leaves project_id empty and carries the ID in service_name.
  # one() errors on several matches, and no match leaves service_name unset,
  # so either way the plan fails rather than guessing.
  cloud_project_id = one([for p in data.ovh_cloud_projects.all.projects : p.service_name if p.description == "o11y-${var.env}"])
  bucket_name      = "futo-o11y-${var.env}-glitchtip"
}

resource "ovh_cloud_project_user" "glitchtip_owner" {
  service_name = local.cloud_project_id
  description  = "o11y-${var.env}-glitchtip-owner"
  role_names   = ["objectstore_operator"]
}

resource "ovh_cloud_project_user" "glitchtip" {
  service_name = local.cloud_project_id
  description  = "o11y-${var.env}-glitchtip"
  role_names   = ["objectstore_operator"]
}

resource "ovh_cloud_project_user_s3_credential" "glitchtip" {
  service_name = local.cloud_project_id
  user_id      = ovh_cloud_project_user.glitchtip.id
}

# Delete is included: GlitchTip removes uploads (and their symbolication
# caches) as it ages them out.
resource "ovh_cloud_project_user_s3_policy" "glitchtip" {
  service_name = local.cloud_project_id
  user_id      = ovh_cloud_project_user.glitchtip.id
  policy = jsonencode({
    Statement = [{
      Sid    = "GlitchTipUploads"
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:ListMultipartUploadParts",
        "s3:ListBucketMultipartUploads",
        "s3:AbortMultipartUpload",
        "s3:GetBucketLocation",
      ]
      Resource = [
        "arn:aws:s3:::${local.bucket_name}",
        "arn:aws:s3:::${local.bucket_name}/*",
      ]
    }]
  })
}

resource "ovh_cloud_project_storage" "glitchtip" {
  service_name = local.cloud_project_id
  region_name  = "GRA"
  name         = local.bucket_name
  owner_id     = tonumber(ovh_cloud_project_user.glitchtip_owner.id)

  encryption = {
    sse_algorithm = "AES256"
  }

  # The object listing would otherwise land in state and grow with every upload.
  hide_objects = true

  # Destroying or replacing the bucket deletes every object in it first.
  lifecycle {
    prevent_destroy = true
  }
}
