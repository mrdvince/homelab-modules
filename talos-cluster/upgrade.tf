resource "null_resource" "upgrade_talos" {
  count = var.auto_upgrade ? 1 : 0

  triggers = {
    installer_image = data.talos_image_factory_urls.this.urls.installer
    nodes           = jsonencode(concat(var.controlplane_nodes, local.worker_node_endpoints))
    target_version  = var.talos_version
  }

  provisioner "local-exec" {
    quiet = true

    command = <<-EOT
      set -eu

      node_name_for_endpoint() {
        kubectl get nodes -o json | jq -r --arg endpoint "$1" '
          .items[] |
          select(any(.status.addresses[]; .type == "InternalIP" and .address == $endpoint)) |
          .metadata.name
        ' | head -n 1
      }

      server_version() {
        talosctl --nodes "$1" version 2>/dev/null |
          awk '/^Server:/{server=1} server && /Tag:/{print $2; exit}'
      }

      for node in $(printf '%s' "$TALOS_NODES" | jq -r '.[]'); do
        current_version=$(server_version "$node")
        if [ -z "$current_version" ]; then
          echo "could not read the Talos version from $node" >&2
          exit 1
        fi

        if [ "$current_version" != "$TALOS_VERSION" ]; then
          echo "upgrading $node from Talos $current_version to $TALOS_VERSION..."
          talosctl --nodes "$node" upgrade --image "$INSTALLER_IMAGE" --drain=false
        else
          echo "$node is already running Talos $TALOS_VERSION"
        fi

        node_name=$(node_name_for_endpoint "$node")
        if [ -z "$node_name" ]; then
          echo "could not find the Kubernetes node for Talos endpoint $node" >&2
          exit 1
        fi

        kubectl wait --for=condition=Ready "node/$node_name" --timeout=10m
      done
    EOT

    environment = {
      INSTALLER_IMAGE = data.talos_image_factory_urls.this.urls.installer
      TALOS_NODES     = jsonencode(concat(var.controlplane_nodes, local.worker_node_endpoints))
      TALOS_VERSION   = var.talos_version
    }
  }
}

resource "null_resource" "upgrade_kubernetes" {
  count = var.auto_upgrade && var.kubernetes_version != null ? 1 : 0

  depends_on = [null_resource.upgrade_talos]

  triggers = {
    external_nodes     = jsonencode(var.external_kubelet_upgrade_commands)
    kubernetes_version = var.kubernetes_version
    talos_nodes        = jsonencode(concat(var.controlplane_nodes, local.worker_node_endpoints))
    talos_version      = var.talos_version
  }

  provisioner "local-exec" {
    quiet = true

    command = <<-EOT
      set -eu

      wait_for_node() {
        node_name="$1"
        kubectl wait \
          --for="jsonpath={.status.nodeInfo.kubeletVersion}=v$KUBERNETES_VERSION" \
          "node/$node_name" \
          --timeout=10m
        kubectl wait --for=condition=Ready "node/$node_name" --timeout=10m
      }

      node_name_for_endpoint() {
        kubectl get nodes -o json | jq -r --arg endpoint "$1" '
          .items[] |
          select(any(.status.addresses[]; .type == "InternalIP" and .address == $endpoint)) |
          .metadata.name
        ' | head -n 1
      }

      echo "converging Kubernetes control plane on v$KUBERNETES_VERSION..."
      talosctl --nodes "$CONTROL_PLANE_NODE" upgrade-k8s --to "$KUBERNETES_VERSION" --upgrade-kubelet=false

      for node in $(printf '%s' "$TALOS_NODES" | jq -r '.[]'); do
        node_name=$(node_name_for_endpoint "$node")
        if [ -z "$node_name" ]; then
          echo "could not find the Kubernetes node for Talos endpoint $node" >&2
          exit 1
        fi

        current_version=$(kubectl get node "$node_name" -o jsonpath='{.status.nodeInfo.kubeletVersion}')
        if [ "$current_version" != "v$KUBERNETES_VERSION" ]; then
          echo "upgrading kubelet on $node_name to v$KUBERNETES_VERSION..."
          talosctl --nodes "$node" patch machineconfig --mode=no-reboot \
            --patch "{\"machine\":{\"kubelet\":{\"image\":\"ghcr.io/siderolabs/kubelet:v$KUBERNETES_VERSION\"}}}"
        else
          echo "$node_name is already running kubelet v$KUBERNETES_VERSION"
        fi
        wait_for_node "$node_name"
      done

      kubernetes_minor=$(printf '%s' "$KUBERNETES_VERSION" | awk -F. '{print $1 "." $2}')
      for node_name in $(printf '%s' "$EXTERNAL_KUBELET_UPGRADE_COMMANDS" | jq -r 'keys[]'); do
        current_version=$(kubectl get node "$node_name" -o jsonpath='{.status.nodeInfo.kubeletVersion}')
        if [ "$current_version" != "v$KUBERNETES_VERSION" ]; then
          upgrade_command=$(printf '%s' "$EXTERNAL_KUBELET_UPGRADE_COMMANDS" | jq -r --arg node "$node_name" '.[$node]')
          echo "upgrading kubelet on external node $node_name to v$KUBERNETES_VERSION..."
          KUBERNETES_MINOR="$kubernetes_minor" sh -c "$upgrade_command"
        else
          echo "$node_name is already running kubelet v$KUBERNETES_VERSION"
        fi
        wait_for_node "$node_name"
      done
    EOT

    environment = {
      CONTROL_PLANE_NODE                = var.controlplane_nodes[0]
      EXTERNAL_KUBELET_UPGRADE_COMMANDS = jsonencode(var.external_kubelet_upgrade_commands)
      KUBERNETES_VERSION                = trimprefix(var.kubernetes_version, "v")
      TALOS_NODES                       = jsonencode(concat(var.controlplane_nodes, local.worker_node_endpoints))
    }
  }
}

resource "null_resource" "reboot_staged_configurations" {
  depends_on = [
    talos_machine_configuration_apply.controlplane,
    talos_machine_configuration_apply.worker,
  ]

  triggers = {
    apply_mode = var.config_apply_mode
    controlplane_configuration_hashes = jsonencode({
      for node, configuration in talos_machine_configuration_apply.controlplane :
      node => configuration.machine_configuration_hash
    })
    worker_configuration_hashes = jsonencode({
      for name, configuration in talos_machine_configuration_apply.worker :
      name => configuration.machine_configuration_hash
    })
  }

  provisioner "local-exec" {
    quiet = true

    command = <<-EOT
      set -eu

      node_name_for_endpoint() {
        kubectl get nodes -o json | jq -r --arg endpoint "$1" '
          .items[] |
          select(any(.status.addresses[]; .type == "InternalIP" and .address == $endpoint)) |
          .metadata.name
        ' | head -n 1
      }

      reboot_nodes() {
        for node in $(printf '%s' "$1" | jq -r '.[]'); do
          node_name=$(node_name_for_endpoint "$node")
          if [ -z "$node_name" ]; then
            echo "could not find the Kubernetes node for Talos endpoint $node" >&2
            exit 1
          fi

          echo "rebooting $node_name to activate its staged Talos configuration..."
          talosctl --nodes "$node" reboot
          kubectl wait --for=condition=Ready "node/$node_name" --timeout=10m
        done
      }

      reboot_nodes "$CONTROL_PLANE_NODES"
      reboot_nodes "$WORKER_NODES"
    EOT

    environment = {
      CONTROL_PLANE_NODES = jsonencode([
        for node, configuration in talos_machine_configuration_apply.controlplane :
        node if configuration.resolved_apply_mode == "staged"
      ])
      WORKER_NODES = jsonencode([
        for name, configuration in talos_machine_configuration_apply.worker :
        local.worker_node_endpoints_by_name[name].endpoint
        if configuration.resolved_apply_mode == "staged"
      ])
    }
  }
}

resource "null_resource" "cleanup_unhealthy_pods" {
  count = var.auto_upgrade ? 1 : 0

  triggers = {
    kubernetes_upgrade_id = var.kubernetes_version != null ? null_resource.upgrade_kubernetes[0].id : ""
    staged_reboot_id      = null_resource.reboot_staged_configurations.id
    talos_upgrade_id      = null_resource.upgrade_talos[0].id
  }

  provisioner "local-exec" {
    quiet = true

    command = <<-EOT
      set -eu

      kubectl get pods --all-namespaces -o json | jq -r '
        .items[] |
        select(
          .status.phase == "Failed" or
          .status.phase == "Unknown" or
          ([
            .status.initContainerStatuses[]?,
            .status.containerStatuses[]?,
            .status.ephemeralContainerStatuses[]?
          ] | any(
            .state.waiting.reason == "ContainerStatusUnknown" or
            .state.waiting.reason == "CrashLoopBackOff" or
            .state.terminated.reason == "ContainerStatusUnknown"
          ))
        ) |
        [.metadata.namespace, .metadata.name] |
        @tsv
      ' | while read -r namespace pod; do
        echo "deleting unhealthy pod $namespace/$pod..."
        kubectl delete pod --namespace "$namespace" "$pod"
      done
    EOT
  }
}
