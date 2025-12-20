provider "helm" {
  kubernetes = {
    host                   = talos_cluster_kubeconfig.this.kubernetes_client_configuration.host
    client_certificate     = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_certificate)
    client_key             = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_key)
    cluster_ca_certificate = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate)
  }
}

resource "helm_release" "cilium" {
  count = var.install_cilium ? 1 : 0

  depends_on = [talos_machine_bootstrap.this]

  name             = "cilium"
  namespace        = "kube-system"
  repository       = "https://helm.cilium.io/"
  chart            = "cilium"
  version          = var.cilium_version
  create_namespace = false

  values = [
    yamlencode({
      kubeProxyReplacement = true
      socketLB = {
        hostNamespaceOnly = true
      }
      k8sServiceHost = var.cilium.k8s_service_host
      k8sServicePort = var.cilium.k8s_service_port
      cgroup = {
        hostRoot = var.cilium.cgroup_host_root
        autoMount = {
          enabled = false
        }
      }
      ipam = {
        mode = "kubernetes"
      }
      ipv4NativeRoutingCIDR = var.kubernetes.pod_subnet
      operator = {
        replicas = var.cilium.operator_replicas
      }
      securityContext = {
        capabilities = {
          cleanCiliumState = ["NET_ADMIN", "SYS_ADMIN", "SYS_RESOURCE"]
          ciliumAgent = [
            "CHOWN", "KILL", "NET_ADMIN", "NET_RAW", "IPC_LOCK",
            "SYS_ADMIN", "SYS_RESOURCE", "DAC_OVERRIDE", "FOWNER", "SETGID", "SETUID"
          ]
        }
      }
    })
  ]
}
