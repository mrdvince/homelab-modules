output "kubeconfig_raw" {
  description = "Raw kubeconfig for the cluster"
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

output "kubernetes_client_configuration" {
  description = "Kubernetes client configuration"
  value       = talos_cluster_kubeconfig.this.kubernetes_client_configuration
  sensitive   = true
}

output "talosconfig" {
  description = "Talos client configuration"
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "client_configuration" {
  description = "Client configuration for other Talos resources"
  value       = talos_machine_secrets.this.client_configuration
  sensitive   = true
}

output "machine_secrets" {
  description = "Machine secrets (for importing existing clusters)"
  value       = talos_machine_secrets.this.machine_secrets
  sensitive   = true
}

output "schematic_id" {
  description = "Image factory schematic ID"
  value       = talos_image_factory_schematic.this.id
}

output "installer_image" {
  description = "Installer image URL (includes extensions if configured)"
  value       = data.talos_image_factory_urls.this.urls.installer
}
