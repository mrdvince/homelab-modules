resource "null_resource" "upgrade_controlplane" {
  count = var.auto_upgrade ? 1 : 0

  depends_on = [helm_release.cilium, null_resource.talosconfig_merge]

  triggers = {
    installer_image = data.talos_image_factory_urls.this.urls.installer
    nodes           = join(",", var.controlplane_nodes)
    target_version  = var.talos_version
  }

  provisioner "local-exec" {
    quiet = true

    command = <<-EOT
      set -eu

      TARGET_VERSION="${var.talos_version}"
      INSTALLER_IMAGE="${data.talos_image_factory_urls.this.urls.installer}"

      read_server_version() {
        talosctl --endpoints "$node" version --nodes "$node" 2>/dev/null | awk '/^Server:/{server=1} server && /Tag:/{print $2; exit}' || true
      }

      wait_for_server_version() {
        for attempt in $(seq 1 30); do
          CURRENT_VERSION=$(read_server_version)
          if [ -n "$CURRENT_VERSION" ]; then
            return 0
          fi
          echo "waiting for Talos API on $node... (attempt $attempt/30)"
          sleep 10
        done

        echo "timed out waiting for Talos API on $node" >&2
        return 1
      }

      wait_for_talos_running() {
        echo "waiting for $node to run Talos $TARGET_VERSION..."
        sleep 30

        for attempt in $(seq 1 60); do
          STAGE=""
          SERVER_VERSION=$(read_server_version)
          if [ "$SERVER_VERSION" = "$TARGET_VERSION" ]; then
            STAGE=$(talosctl --endpoints "$node" get machinestatus --nodes "$node" -o jsonpath='{.spec.stage}' 2>/dev/null || echo "")
            if [ "$STAGE" = "running" ]; then
              echo "$node is running Talos $TARGET_VERSION"
              return 0
            fi
          fi

          echo "waiting for $node... version='$SERVER_VERSION' stage='$STAGE' (attempt $attempt/60)"
          sleep 10
        done

        echo "timed out waiting for $node to run Talos $TARGET_VERSION; last version='$SERVER_VERSION' stage='$STAGE'" >&2
        return 1
      }

      wait_for_kubernetes_ready_by_ip() {
        echo "waiting for kubernetes node at $node to be Ready..."

        for attempt in $(seq 1 60); do
          NODE_NAME=$(kubectl get nodes -o json | jq -r '.items[] | select(.status.addresses[] | select(.type=="InternalIP" and .address=="'"$node"'")) | .metadata.name' | head -n1)
          if [ -n "$NODE_NAME" ] && kubectl get node "$NODE_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
            echo "$node ($NODE_NAME) upgrade complete"
            return 0
          fi

          echo "waiting for kubernetes node at $node... (attempt $attempt/60)"
          sleep 5
        done

        echo "timed out waiting for kubernetes node for $node to become Ready" >&2
        return 1
      }

      upgrade_node() {
        node="$1"

        wait_for_server_version
        CURRENT_VERSION=$(read_server_version)

        if [ "$CURRENT_VERSION" = "$TARGET_VERSION" ]; then
          echo "$node is already running Talos $TARGET_VERSION"
          return 0
        fi

        echo "upgrading $node from Talos $CURRENT_VERSION to $TARGET_VERSION..."
        talosctl --endpoints "$node" upgrade --nodes "$node" --image "$INSTALLER_IMAGE" --wait=false

        wait_for_talos_running
        wait_for_kubernetes_ready_by_ip
      }

      for node in ${join(" ", var.controlplane_nodes)}; do
        upgrade_node "$node"
      done
    EOT
  }
}

resource "null_resource" "upgrade_workers" {
  count = var.auto_upgrade && length(local.worker_node_endpoints_by_name) > 0 ? 1 : 0

  depends_on = [null_resource.upgrade_controlplane, talos_machine_configuration_apply.worker]

  triggers = {
    installer_image = data.talos_image_factory_urls.this.urls.installer
    nodes           = join(",", local.worker_node_endpoints)
    target_version  = var.talos_version
  }

  provisioner "local-exec" {
    quiet = true

    command = <<-EOT
      set -eu

      TARGET_VERSION="${var.talos_version}"
      INSTALLER_IMAGE="${data.talos_image_factory_urls.this.urls.installer}"
      WORKERS='${jsonencode([
    for node_name, node in local.worker_node_endpoints_by_name : {
      name     = node_name
      endpoint = node.endpoint
    }
])}'

      read_server_version() {
        talosctl --endpoints "$node" version --nodes "$node" 2>/dev/null | awk '/^Server:/{server=1} server && /Tag:/{print $2; exit}' || true
      }

      wait_for_server_version() {
        for attempt in $(seq 1 30); do
          CURRENT_VERSION=$(read_server_version)
          if [ -n "$CURRENT_VERSION" ]; then
            return 0
          fi
          echo "waiting for Talos API on $node... (attempt $attempt/30)"
          sleep 10
        done

        echo "timed out waiting for Talos API on $node" >&2
        return 1
      }

      wait_for_talos_running() {
        echo "waiting for $node to run Talos $TARGET_VERSION..."
        sleep 30

        for attempt in $(seq 1 60); do
          STAGE=""
          SERVER_VERSION=$(read_server_version)
          if [ "$SERVER_VERSION" = "$TARGET_VERSION" ]; then
            STAGE=$(talosctl --endpoints "$node" get machinestatus --nodes "$node" -o jsonpath='{.spec.stage}' 2>/dev/null || echo "")
            if [ "$STAGE" = "running" ]; then
              echo "$node is running Talos $TARGET_VERSION"
              return 0
            fi
          fi

          echo "waiting for $node... version='$SERVER_VERSION' stage='$STAGE' (attempt $attempt/60)"
          sleep 10
        done

        echo "timed out waiting for $node to run Talos $TARGET_VERSION; last version='$SERVER_VERSION' stage='$STAGE'" >&2
        return 1
      }

      wait_for_kubernetes_ready_by_name() {
        echo "waiting for kubernetes node $NODE_NAME to be Ready..."

        for attempt in $(seq 1 60); do
          if kubectl get node "$NODE_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
            echo "$node ($NODE_NAME) upgrade complete"
            return 0
          fi

          echo "waiting for kubernetes node $NODE_NAME... (attempt $attempt/60)"
          sleep 5
        done

        echo "timed out waiting for kubernetes node $NODE_NAME to become Ready" >&2
        return 1
      }

      upgrade_node() {
        node="$1"
        NODE_NAME="$2"

        wait_for_server_version
        CURRENT_VERSION=$(read_server_version)

        if [ "$CURRENT_VERSION" = "$TARGET_VERSION" ]; then
          echo "$node ($NODE_NAME) is already running Talos $TARGET_VERSION"
          return 0
        fi

        echo "upgrading $node ($NODE_NAME) from Talos $CURRENT_VERSION to $TARGET_VERSION..."
        talosctl --endpoints "$node" upgrade --nodes "$node" --image "$INSTALLER_IMAGE" --wait=false

        wait_for_talos_running
        wait_for_kubernetes_ready_by_name
      }

      worker_count=$(printf '%s' "$WORKERS" | jq 'length')
      worker_index=0
      while [ "$worker_index" -lt "$worker_count" ]; do
        node=$(printf '%s' "$WORKERS" | jq -r ".[$worker_index].endpoint")
        NODE_NAME=$(printf '%s' "$WORKERS" | jq -r ".[$worker_index].name")
        upgrade_node "$node" "$NODE_NAME"
        worker_index=$((worker_index + 1))
      done
    EOT
}
}
