terraform {
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "2026.2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.0"
    }
  }
}

provider "authentik" {
  url   = var.authentik_url
  token = var.authentik_token
}
