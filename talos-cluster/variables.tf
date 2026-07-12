variable "cluster_name" {
  description = "Name of the Talos cluster"
  type        = string
}

variable "cluster_endpoint" {
  description = "Kubernetes API endpoint (VIP address with port)"
  type        = string
}

variable "controlplane_nodes" {
  description = "List of control plane node IPs"
  type        = list(string)
}

variable "talos_endpoints" {
  description = "Endpoints for talosctl (defaults to VIP if set, otherwise controlplane nodes)"
  type        = list(string)
  default     = null
}

variable "worker_nodes" {
  description = "List of worker node IPs"
  type        = list(string)
  default     = []
}

variable "worker_node_ips" {
  description = "Map of worker node names to IPs"
  type        = map(string)
  default     = {}
}

variable "worker_node_endpoints" {
  description = "Map of worker node names to Talos API endpoints"
  type = map(object({
    endpoint = string
  }))
  default = {}
}

variable "talos_version" {
  description = "Talos version for machine configuration"
  type        = string
  default     = null
}

variable "kubernetes_version" {
  description = "Target Kubernetes patch version. Kubernetes is upgraded after Talos and before the generated machine configuration is reapplied."
  type        = string
  default     = null

  validation {
    condition     = var.kubernetes_version == null || can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must be an exact patch version such as 1.36.2."
  }
}

variable "external_kubelet_upgrade_commands" {
  description = "Commands for non-Talos nodes, keyed by Kubernetes node name. KUBERNETES_VERSION and KUBERNETES_MINOR are set for each upgrade step."
  type        = map(string)
  default     = {}
}

variable "config_patches" {
  description = "Common config patches applied to all nodes"
  type        = list(string)
  default     = []
}

variable "ethernet_configs" {
  description = "Talos EthernetConfig documents applied to all nodes"
  type = list(object({
    name     = string
    features = optional(map(bool), {})
  }))
  default = []
}

variable "controlplane_patches" {
  description = "Config patches applied only to control plane nodes"
  type        = list(string)
  default     = []
}

variable "worker_patches" {
  description = "Config patches applied only to worker nodes"
  type        = list(string)
  default     = []
}

variable "worker_node_patches" {
  description = "Config patches applied to individual worker nodes, keyed by worker node name"
  type        = map(list(string))
  default     = {}
}

variable "worker_node_initial_taints" {
  description = "Initial kubelet registerWithTaints entries for individual worker nodes, keyed by worker node name. Talos only applies these when the Kubernetes Node object is first registered."
  type = map(list(object({
    key    = string
    value  = optional(string)
    effect = string
  })))
  default = {}
}

variable "kubernetes" {
  description = "Kubernetes configuration"
  type = object({
    pod_subnet     = optional(string, "10.244.0.0/16")
    service_subnet = optional(string, "10.96.0.0/16")
  })
  default = {}
}

variable "network" {
  description = "Network configuration"
  type = object({
    interface   = optional(string, "eth0")
    vip         = optional(string)
    nameservers = optional(list(string), ["1.1.1.1", "8.8.8.8"])
  })
  default = {}
}

variable "allow_scheduling_on_controlplanes" {
  description = "Allow workloads to be scheduled on control plane nodes"
  type        = bool
  default     = true
}

variable "disable_kube_proxy" {
  description = "Disable kube-proxy (for CNI like Cilium)"
  type        = bool
  default     = true
}

variable "cni" {
  description = "CNI plugin to use (none, flannel, etc.)"
  type        = string
  default     = "none"
}

variable "install_cilium" {
  description = "Install Cilium CNI via Helm"
  type        = bool
  default     = true
}

variable "cilium_version" {
  description = "Cilium Helm chart version"
  type        = string
  default     = "1.18.4"
}

variable "cilium" {
  description = "Cilium configuration"
  type = object({
    k8s_service_host  = optional(string, "localhost")
    k8s_service_port  = optional(number, 7445)
    cgroup_host_root  = optional(string, "/sys/fs/cgroup")
    operator_replicas = optional(number, 2)
  })
  default = {}
}

variable "extensions" {
  description = "List of Talos system extensions to install (e.g., qemu-guest-agent, iscsi-tools)"
  type        = list(string)
  default     = []
}

variable "auto_upgrade" {
  description = "Automatically upgrade nodes when talos_version or extensions change"
  type        = bool
  default     = false
}

variable "config_apply_mode" {
  description = "Talos machine configuration apply mode"
  type        = string
  default     = "staged_if_needing_reboot"

  validation {
    condition = contains([
      "auto",
      "reboot",
      "no_reboot",
      "staged",
      "staged_if_needing_reboot",
    ], var.config_apply_mode)
    error_message = "config_apply_mode must be a mode supported by the Talos provider."
  }
}
