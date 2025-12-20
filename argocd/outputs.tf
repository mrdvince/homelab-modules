output "namespace" {
  description = "ArgoCD namespace"
  value       = kubernetes_namespace_v1.argocd.metadata[0].name
}

output "chart_version" {
  description = "Installed ArgoCD chart version"
  value       = helm_release.argocd.version
}
