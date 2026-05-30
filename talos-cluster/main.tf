resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

locals {
  raw_worker_node_endpoints_by_name = length(var.worker_node_endpoints) > 0 ? var.worker_node_endpoints : length(var.worker_node_ips) > 0 ? {
    for name, endpoint in var.worker_node_ips : name => { endpoint = endpoint }
    } : {
    for worker_node in var.worker_nodes : worker_node => { endpoint = worker_node }
  }
  worker_node_endpoints_by_name = {
    for name, node in local.raw_worker_node_endpoints_by_name : name => node
    if node.endpoint != null
  }
  worker_node_endpoints = [
    for node in values(local.worker_node_endpoints_by_name) : node.endpoint
  ]

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
                audit             = "privileged"
                "audit-version"   = "latest"
                enforce           = "privileged"
                "enforce-version" = "latest"
                warn              = "privileged"
                "warn-version"    = "latest"
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

  ethernet_config_patches = [
    for ethernet_config in var.ethernet_configs : yamlencode({
      apiVersion = "v1alpha1"
      kind       = "EthernetConfig"
      name       = ethernet_config.name
      features   = ethernet_config.features
    })
  ]

  controlplane_config_patches = concat(
    [local.base_config_patch],
    local.ethernet_config_patches,
    var.config_patches,
    var.controlplane_patches
  )

  worker_config_patches = concat(
    local.ethernet_config_patches,
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
  count            = length(local.worker_node_endpoints_by_name) > 0 ? 1 : 0
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
  apply_mode                  = var.config_apply_mode
}

resource "talos_machine_configuration_apply" "worker" {
  for_each                    = local.worker_node_endpoints_by_name
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker[0].machine_configuration
  node                        = each.value.endpoint
  config_patches = concat(
    local.worker_config_patches,
    [
      yamlencode({
        machine = {
          network = {
            hostname = each.key
          }
        }
      })
    ],
    length(lookup(var.worker_node_initial_taints, each.key, [])) > 0 ? [
      yamlencode({
        machine = {
          kubelet = {
            extraConfig = {
              registerWithTaints = [
                for taint in lookup(var.worker_node_initial_taints, each.key, []) : merge(
                  {
                    key    = taint.key
                    effect = taint.effect
                  },
                  taint.value != null ? { value = taint.value } : {}
                )
              ]
            }
          }
        }
      })
    ] : [],
    lookup(var.worker_node_patches, each.key, [])
  )
  apply_mode = var.config_apply_mode
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

      # check if other clusters exist (contexts not matching our cluster name)
      # column 2 is NAME when current (*), column 1 when not current
      OTHER_CTX=$(talosctl config contexts 2>/dev/null | awk 'NR>1 && !/'"${var.cluster_name}"'/ {print ($1=="*" ? $2 : $1); exit}')

      if [ -z "$OTHER_CTX" ]; then
        # no other clusters, safe to overwrite entirely
        mv talosconfig-${var.cluster_name}.yaml ~/.talos/config
      else
        # other clusters exist, need to preserve them
        # switch to another context first so we can remove ours
        talosctl config context "$OTHER_CTX"
        for ctx in $(talosctl config contexts 2>/dev/null | awk '/'"${var.cluster_name}"'/ {print ($1=="*" ? $2 : $1)}'); do
          talosctl config remove "$ctx" --noconfirm 2>/dev/null || true
        done
        talosctl config merge talosconfig-${var.cluster_name}.yaml
        rm -f talosconfig-${var.cluster_name}.yaml
      fi

      talosctl config context ${var.cluster_name}
    EOT
  }
}
