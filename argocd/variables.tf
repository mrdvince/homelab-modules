variable "kubernetes_host" {
  description = "Kubernetes API server host"
  type        = string
}

variable "kubernetes_client_certificate" {
  description = "Kubernetes client certificate (base64 encoded)"
  type        = string
  sensitive   = true
}

variable "kubernetes_client_key" {
  description = "Kubernetes client key (base64 encoded)"
  type        = string
  sensitive   = true
}

variable "kubernetes_ca_certificate" {
  description = "Kubernetes CA certificate (base64 encoded)"
  type        = string
  sensitive   = true
}

variable "chart_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "9.1.7"
}

variable "namespace" {
  description = "Kubernetes namespace to install ArgoCD"
  type        = string
  default     = "argocd"
}

variable "sops_age_key" {
  description = "SOPS age key for decrypting secrets"
  type        = string
  sensitive   = true
}

variable "helmfile_image" {
  description = "Helmfile sidecar image for CMP plugin"
  type        = string
  default     = "ghcr.io/helmfile/helmfile:v1.2.2"
}

variable "values" {
  description = "Additional values to merge with ArgoCD helm release"
  type        = any
  default     = {}
}

variable "repositories" {
  description = "Git repositories to configure in ArgoCD"
  type = map(object({
    url         = string
    ssh_key     = optional(string)
    type        = optional(string, "git")
    insecure    = optional(bool, false)
  }))
  default = {}
}

variable "root_app" {
  description = "Root ArgoCD Application configuration"
  type = object({
    enabled         = optional(bool, true)
    repo_url        = string
    path            = optional(string, "apps/_argocd")
    target_revision = optional(string, "HEAD")
    env_name        = string
  })
  default = null
}
