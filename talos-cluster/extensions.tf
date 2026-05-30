data "talos_image_factory_extensions_versions" "this" {
  count         = length(var.extensions) > 0 ? 1 : 0
  talos_version = var.talos_version
  filters = {
    names = var.extensions
  }
}

resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode(
    length(var.extensions) > 0 ? {
      customization = {
        systemExtensions = {
          officialExtensions = data.talos_image_factory_extensions_versions.this[0].extensions_info[*].name
        }
      }
    } : {}
  )
}

data "talos_image_factory_urls" "this" {
  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = "nocloud"
}

resource "null_resource" "upgrade_controlplane" {
  count = var.auto_upgrade ? 1 : 0

  depends_on = [helm_release.cilium, null_resource.talosconfig_merge]

  triggers = {
    installer_image = data.talos_image_factory_urls.this.urls.installer
    nodes           = join(",", var.controlplane_nodes)
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -eu

      TARGET_VERSION="${var.talos_version}"
      for node in ${join(" ", var.controlplane_nodes)}; do
        CURRENT_VERSION=$(talosctl --endpoints "$node" version --nodes "$node" 2>/dev/null | awk '/^Server:/{server=1} server && /Tag:/{print $2; exit}' || true)
        if [ "$CURRENT_VERSION" = "$TARGET_VERSION" ]; then
          echo "$node is already running $TARGET_VERSION"
        else
          echo "upgrading $node from $CURRENT_VERSION to $TARGET_VERSION..."
          talosctl --endpoints "$node" upgrade --nodes "$node" --image ${data.talos_image_factory_urls.this.urls.installer} --wait=false
        fi

        echo "waiting for $node to reboot and come back..."
        sleep 30

        for i in $(seq 1 60); do
          STAGE=""
          SERVER_VERSION=$(talosctl --endpoints "$node" version --nodes "$node" 2>/dev/null | awk '/^Server:/{server=1} server && /Tag:/{print $2; exit}' || true)
          if [ "$SERVER_VERSION" = "$TARGET_VERSION" ]; then
            STAGE=$(talosctl --endpoints "$node" get machinestatus --nodes "$node" -o jsonpath='{.spec.stage}' 2>/dev/null || echo "")
            if [ "$STAGE" = "running" ]; then
              echo "$node is running $TARGET_VERSION"
              break
            fi
          fi
          if [ "$i" = "60" ]; then
            echo "timed out waiting for $node to run $TARGET_VERSION; last version='$SERVER_VERSION' stage='$STAGE'" >&2
            exit 1
          fi
          echo "waiting for $node... (attempt $i/60)"
          sleep 10
        done

        echo "waiting for kubernetes node to be ready..."
        for i in $(seq 1 60); do
          NODE_NAME=$(kubectl get nodes -o json | jq -r '.items[] | select(.status.addresses[] | select(.type=="InternalIP" and .address=="'"$node"'")) | .metadata.name' | head -n1)
          if [ -n "$NODE_NAME" ] && kubectl get node "$NODE_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
            echo "$node ($NODE_NAME) upgrade complete"
            break
          fi
          if [ "$i" = "60" ]; then
            echo "timed out waiting for kubernetes node for $node to become Ready" >&2
            exit 1
          fi
          sleep 5
        done
      done
    EOT
  }
}

resource "null_resource" "upgrade_workers" {
  count = var.auto_upgrade && length(var.worker_nodes) > 0 ? 1 : 0

  depends_on = [null_resource.upgrade_controlplane]

  triggers = {
    installer_image = data.talos_image_factory_urls.this.urls.installer
    nodes           = join(",", var.worker_nodes)
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -eu

      TARGET_VERSION="${var.talos_version}"
      for node in ${join(" ", var.worker_nodes)}; do
        CURRENT_VERSION=$(talosctl --endpoints "$node" version --nodes "$node" 2>/dev/null | awk '/^Server:/{server=1} server && /Tag:/{print $2; exit}' || true)
        if [ "$CURRENT_VERSION" = "$TARGET_VERSION" ]; then
          echo "$node is already running $TARGET_VERSION"
        else
          echo "upgrading $node from $CURRENT_VERSION to $TARGET_VERSION..."
          talosctl --endpoints "$node" upgrade --nodes "$node" --image ${data.talos_image_factory_urls.this.urls.installer} --wait=false
        fi

        echo "waiting for $node to reboot and come back..."
        sleep 30

        for i in $(seq 1 60); do
          STAGE=""
          SERVER_VERSION=$(talosctl --endpoints "$node" version --nodes "$node" 2>/dev/null | awk '/^Server:/{server=1} server && /Tag:/{print $2; exit}' || true)
          if [ "$SERVER_VERSION" = "$TARGET_VERSION" ]; then
            STAGE=$(talosctl --endpoints "$node" get machinestatus --nodes "$node" -o jsonpath='{.spec.stage}' 2>/dev/null || echo "")
            if [ "$STAGE" = "running" ]; then
              echo "$node is running $TARGET_VERSION"
              break
            fi
          fi
          if [ "$i" = "60" ]; then
            echo "timed out waiting for $node to run $TARGET_VERSION; last version='$SERVER_VERSION' stage='$STAGE'" >&2
            exit 1
          fi
          echo "waiting for $node... (attempt $i/60)"
          sleep 10
        done

        echo "waiting for kubernetes node to be ready..."
        for i in $(seq 1 60); do
          NODE_NAME=$(kubectl get nodes -o json | jq -r '.items[] | select(.status.addresses[] | select(.type=="InternalIP" and .address=="'"$node"'")) | .metadata.name' | head -n1)
          if [ -n "$NODE_NAME" ] && kubectl get node "$NODE_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
            echo "$node ($NODE_NAME) upgrade complete"
            break
          fi
          if [ "$i" = "60" ]; then
            echo "timed out waiting for kubernetes node for $node to become Ready" >&2
            exit 1
          fi
          sleep 5
        done
      done
    EOT
  }
}
