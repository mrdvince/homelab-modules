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
      TARGET_VERSION="${var.talos_version}"
      for node in ${join(" ", var.controlplane_nodes)}; do
        echo "upgrading $node to $TARGET_VERSION..."
        talosctl upgrade --nodes "$node" --image ${data.talos_image_factory_urls.this.urls.installer} --preserve

        echo "waiting for $node to reboot and come back..."
        sleep 30

        for i in $(seq 1 60); do
          if talosctl version --nodes "$node" 2>/dev/null | grep -q "$TARGET_VERSION"; then
            STAGE=$(talosctl get machinestatus --nodes "$node" -o jsonpath='{.spec.stage}' 2>/dev/null || echo "")
            if [ "$STAGE" = "running" ]; then
              echo "$node is running $TARGET_VERSION"
              break
            fi
          fi
          echo "waiting for $node... (attempt $i/60)"
          sleep 10
        done

        echo "waiting for kubernetes node to be ready..."
        until kubectl get node "$node" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; do
          sleep 5
        done
        echo "$node upgrade complete"
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
      TARGET_VERSION="${var.talos_version}"
      for node in ${join(" ", var.worker_nodes)}; do
        echo "upgrading $node to $TARGET_VERSION..."
        talosctl upgrade --nodes "$node" --image ${data.talos_image_factory_urls.this.urls.installer} --preserve

        echo "waiting for $node to reboot and come back..."
        sleep 30

        for i in $(seq 1 60); do
          if talosctl version --nodes "$node" 2>/dev/null | grep -q "$TARGET_VERSION"; then
            STAGE=$(talosctl get machinestatus --nodes "$node" -o jsonpath='{.spec.stage}' 2>/dev/null || echo "")
            if [ "$STAGE" = "running" ]; then
              echo "$node is running $TARGET_VERSION"
              break
            fi
          fi
          echo "waiting for $node... (attempt $i/60)"
          sleep 10
        done

        echo "waiting for kubernetes node to be ready..."
        until kubectl get node "$node" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; do
          sleep 5
        done
        echo "$node upgrade complete"
      done
    EOT
  }
}
