terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.2"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.3.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0"
    }
  }
}
