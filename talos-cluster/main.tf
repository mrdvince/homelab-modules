resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

locals {
  base_config_patch = yamlencode({
    machine = {
      network = {
        interfaces = [
          {
            interface = var.network.interface
            dhcp      = true
            vip = var.network.vip != null ? {
              ip = var.network.vip
            } : null
          }
        ]
        nameservers = var.network.nameservers
      }
    }
    cluster = {
      allowSchedulingOnControlPlanes = var.allow_scheduling_on_controlplanes
      apiServer = {
        certSANs = var.controlplane_nodes
        admissionControl = [
          {
            name = "PodSecurity"
            configuration = {
              defaults = {
                audit            = "privileged"
                "audit-version"  = "latest"
                enforce          = "privileged"
                "enforce-version" = "latest"
                warn             = "privileged"
                "warn-version"   = "latest"
              }
            }
          }
        ]
      }
      network = {
        cni = {
          name = var.cni
        }
        podSubnets     = [var.kubernetes.pod_subnet]
        serviceSubnets = [var.kubernetes.service_subnet]
      }
      proxy = {
        disabled = var.disable_kube_proxy
      }
    }
  })

  controlplane_config_patches = concat(
    [local.base_config_patch],
    var.config_patches,
    var.controlplane_patches
  )

  worker_config_patches = concat(
    var.config_patches,
    var.worker_patches
  )
}

data "talos_machine_configuration" "controlplane" {
  cluster_name     = var.cluster_name
  machine_type     = "controlplane"
  cluster_endpoint = var.cluster_endpoint
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = var.talos_version
}

data "talos_machine_configuration" "worker" {
  count            = length(var.worker_nodes) > 0 ? 1 : 0
  cluster_name     = var.cluster_name
  machine_type     = "worker"
  cluster_endpoint = var.cluster_endpoint
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = var.talos_version
}

locals {
  talos_endpoints = coalesce(
    var.talos_endpoints,
    var.network.vip != null ? [var.network.vip] : var.controlplane_nodes
  )
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = var.controlplane_nodes
  endpoints            = local.talos_endpoints
}

resource "talos_machine_configuration_apply" "controlplane" {
  for_each                    = toset(var.controlplane_nodes)
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = each.value
  config_patches              = local.controlplane_config_patches
}

resource "talos_machine_configuration_apply" "worker" {
  for_each                    = toset(var.worker_nodes)
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker[0].machine_configuration
  node                        = each.value
  config_patches              = local.worker_config_patches
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.controlplane]

  node                 = var.controlplane_nodes[0]
  client_configuration = talos_machine_secrets.this.client_configuration
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_machine_bootstrap.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.controlplane_nodes[0]
}

resource "null_resource" "kubeconfig_merge" {
  depends_on = [talos_cluster_kubeconfig.this]

  triggers = {
    kubeconfig = talos_cluster_kubeconfig.this.kubeconfig_raw
  }

  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ~/.kube
      echo '${talos_cluster_kubeconfig.this.kubeconfig_raw}' > kubeconfig-${var.cluster_name}.yaml
      KUBECONFIG=~/.kube/config:kubeconfig-${var.cluster_name}.yaml kubectl config view --flatten > ~/.kube/config.merged
      mv ~/.kube/config.merged ~/.kube/config
      chmod 600 ~/.kube/config
      rm -f kubeconfig-${var.cluster_name}.yaml
      kubectl config use-context admin@${var.cluster_name}
    EOT
  }
}

resource "null_resource" "talosconfig_merge" {
  depends_on = [talos_cluster_kubeconfig.this]

  triggers = {
    talosconfig = data.talos_client_configuration.this.talos_config
  }

  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ~/.talos
      echo '${data.talos_client_configuration.this.talos_config}' > talosconfig-${var.cluster_name}.yaml
      talosctl config merge talosconfig-${var.cluster_name}.yaml
      rm -f talosconfig-${var.cluster_name}.yaml
      talosctl config context ${var.cluster_name}
    EOT
  }
}
