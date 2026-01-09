data "terraform_remote_state" "talos_state" {
  backend = "s3"

  config = {
    bucket = var.tf_state_s3_bucket
    key    = "yucca/o11y/ovh/account/${var.env}${var.stage != "" ? "/${var.stage}" : ""}"
    region = var.tf_state_s3_region
    access_key = var.tf_state_s3_access_key
    secret_key = var.tf_state_s3_secret_key

    endpoints = {
      s3 = var.tf_state_s3_endpoint
    }

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
  }
}
