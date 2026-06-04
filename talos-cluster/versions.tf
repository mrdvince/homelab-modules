terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "3.2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.3.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.9.0"
    }
  }
}
