provider "ovh" {
  endpoint           = "ovh-eu"
  application_key    = var.ovh_application_key
  application_secret = var.ovh_application_secret
  consumer_key       = var.ovh_consumer_key
}

provider "tailscale" {

}

# provider "ovh" {
#   alias              = "soyoustart"
#   endpoint           = "kimsufi-eu"
#   application_key    = var.ovh_application_key
#   application_secret = var.ovh_application_secret
#   consumer_key       = var.ovh_consumer_key
# }


