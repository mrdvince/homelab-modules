locals {
  ssh_target = var.ssh_host_alias != null ? var.ssh_host_alias : var.host != null ? "${var.ssh_user}@${var.host}" : ""
  remote_dir = var.remote_dir != null ? var.remote_dir : "/etc/olly/${var.name}"

  all_files = merge(var.files, nonsensitive(var.secret_files))

  file_env = {
    for filename, file in local.all_files :
    "OLLY_FILE_${substr(sha1(filename), 0, 12)}" => base64encode(file.content)
  }

  upload_files = [
    for filename, file in local.all_files : {
      env_name = "OLLY_FILE_${substr(sha1(filename), 0, 12)}"
      filename = replace(filename, "'", "'\\''")
      basename = replace(basename(filename), "'", "'\\''")
      mode     = file.mode
      owner    = replace(file.owner, "'", "'\\''")
      group    = replace(file.group, "'", "'\\''")
    }
  ]

  containers = {
    for key, container in var.containers : key => merge(container, {
      container_name = coalesce(container.container_name, key)
    })
  }

  container_names = join(" ", [for _, container in local.containers : container.container_name])

  setup_script = templatefile("${path.module}/templates/setup.sh.tftpl", {
    remote_dir = local.remote_dir
    containers = local.containers
  })

  upload_script = templatefile("${path.module}/templates/upload.sh.tftpl", {
    remote_dir   = replace(local.remote_dir, "'", "'\\''")
    upload_files = local.upload_files
  })
}

resource "local_file" "files" {
  for_each = var.render_local_files ? var.files : {}

  filename        = "${path.root}/${var.render_local_dir}/${each.key}"
  content         = each.value.content
  file_permission = each.value.mode
}

resource "local_file" "setup_script" {
  count = var.render_local_files ? 1 : 0

  filename        = "${path.root}/${var.render_local_dir}/setup.sh"
  content         = local.setup_script
  file_permission = "0644"
}

resource "null_resource" "apply" {
  triggers = {
    ssh_target          = local.ssh_target
    ssh_options         = join("\n", var.ssh_options)
    remote_dir          = local.remote_dir
    container_names     = local.container_names
    files_sha256        = sha256(jsonencode({ for name, file in var.files : name => { content = file.content, mode = file.mode, owner = file.owner, group = file.group } }))
    secret_files_sha256 = nonsensitive(sha256(jsonencode({ for name, file in var.secret_files : name => { content = file.content, mode = file.mode, owner = file.owner, group = file.group } })))
    containers_sha256   = sha256(jsonencode(var.containers))
    setup_sha256        = sha256(local.setup_script)
    upload_sha256       = sha256(local.upload_script)
  }

  lifecycle {
    precondition {
      condition     = local.ssh_target != ""
      error_message = "Either ssh_host_alias or host must be set."
    }
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = merge(local.file_env, {
      OLLY_SSH_TARGET  = self.triggers.ssh_target
      OLLY_SSH_OPTIONS = self.triggers.ssh_options
      OLLY_SETUP_B64   = base64encode(local.setup_script)
    })
    command = local.upload_script
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    environment = {
      OLLY_SSH_TARGET      = self.triggers.ssh_target
      OLLY_SSH_OPTIONS     = self.triggers.ssh_options
      OLLY_REMOTE_DIR      = self.triggers.remote_dir
      OLLY_CONTAINER_NAMES = self.triggers.container_names
    }
    command = <<-EOT
      set -euo pipefail

      ssh_options=()
      while IFS= read -r option; do
        [ -n "$option" ] && ssh_options+=("$option")
      done <<< "$OLLY_SSH_OPTIONS"

      ssh "$${ssh_options[@]}" "$OLLY_SSH_TARGET" "docker rm -f $OLLY_CONTAINER_NAMES >/dev/null 2>&1 || true; rm -rf '$OLLY_REMOTE_DIR' >/dev/null 2>&1 || true"
    EOT
  }
}
