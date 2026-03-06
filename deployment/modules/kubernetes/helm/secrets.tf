resource "random_password" "vmauth_external_reader" {
  length  = 32
  special = false
}

resource "random_password" "vmauth_external_writer" {
  length  = 32
  special = false
}

resource "random_password" "vmauth_internal_reader" {
  length  = 32
  special = false
}

resource "random_password" "vmauth_internal_writer" {
  length  = 32
  special = false
}
