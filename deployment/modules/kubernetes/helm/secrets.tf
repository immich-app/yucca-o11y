resource "random_password" "vmauth_reader" {
  length  = 32
  special = false
}

resource "random_password" "vmauth_writer" {
  length  = 32
  special = false
}

resource "random_password" "vmauth_internal_reader" {
  length  = 32
  special = false
}

resource "random_password" "vmagent" {
  length  = 32
  special = false
}
