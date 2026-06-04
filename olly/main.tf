locals {
  logs_config = templatefile("${path.module}/templates/logs.alloy.tftpl", {
    instance      = var.instance
    platform      = var.platform
    loki_url      = var.loki_url != null ? var.loki_url : ""
    loki_username = var.loki_username
    file_logs     = var.file_logs
  })

  logs_setup_script = file("${path.module}/templates/setup.sh")

  shell_loki_password = replace(var.loki_password != null ? var.loki_password : "", "'", "'\"'\"'")
  shell_loki_username = replace(var.loki_username, "'", "'\"'\"'")

  logs_bootstrap_env = <<-EOF
    LOKI_USERNAME='${local.shell_loki_username}'
    LOKI_PASSWORD='${local.shell_loki_password}'
  EOF

  metrics_config = templatefile("${path.module}/templates/metrics.alloy.tftpl", {
    instance                    = var.instance
    platform                    = var.platform
    create_pve_exporter         = var.create_pve_exporter
    prometheus_remote_write_url = var.prometheus_remote_write_url != null ? var.prometheus_remote_write_url : ""
    prometheus_username         = var.prometheus_username
    pve_exporter_target         = local.pve_exporter_target
  })

  metrics_setup_script = file("${path.module}/templates/setup-metrics.sh")

  pve_token_parts = split("!", var.pve_exporter_token_id != null ? var.pve_exporter_token_id : "!")

  pve_exporter_user       = local.pve_token_parts[0]
  pve_exporter_token_name = local.pve_token_parts[1]

  shell_prometheus_password     = replace(var.prometheus_password != null ? var.prometheus_password : "", "'", "'\"'\"'")
  shell_pve_exporter_user       = replace(local.pve_exporter_user, "'", "'\"'\"'")
  shell_pve_exporter_token_name = replace(local.pve_exporter_token_name, "'", "'\"'\"'")
  shell_pve_exporter_secret     = replace(var.pve_exporter_token_secret != null ? var.pve_exporter_token_secret : "", "'", "'\"'\"'")
  shell_pve_exporter_image      = replace(var.pve_exporter_image, "'", "'\"'\"'")
  shell_pve_exporter_platform   = replace(var.pve_exporter_platform, "'", "'\"'\"'")
  shell_pve_exporter_target     = replace(local.pve_exporter_target, "'", "'\"'\"'")

  metrics_bootstrap_env = <<-EOF
    PROMETHEUS_PASSWORD='${local.shell_prometheus_password}'
    PVE_EXPORTER_ENABLED='${var.create_pve_exporter ? "true" : "false"}'
    PVE_EXPORTER_USER='${local.shell_pve_exporter_user}'
    PVE_EXPORTER_TOKEN_NAME='${local.shell_pve_exporter_token_name}'
    PVE_EXPORTER_TOKEN_SECRET='${local.shell_pve_exporter_secret}'
    PVE_EXPORTER_IMAGE='${local.shell_pve_exporter_image}'
    PVE_EXPORTER_PLATFORM='${local.shell_pve_exporter_platform}'
    PVE_EXPORTER_TARGET='${local.shell_pve_exporter_target}'
  EOF

  ssh_target = var.ssh_host_alias != null ? var.ssh_host_alias : var.host != null ? "${var.ssh_user}@${var.host}" : ""

  pve_exporter_target = var.pve_exporter_target != null ? var.pve_exporter_target : var.host != null ? var.host : ""
}

resource "local_file" "logs_config" {
  count = var.create_logs && var.render_local_files ? 1 : 0

  filename        = "${path.root}/${var.render_local_dir}/config.alloy"
  content         = local.logs_config
  file_permission = "0644"
}

resource "local_file" "logs_setup_script" {
  count = var.create_logs && var.render_local_files ? 1 : 0

  filename        = "${path.root}/${var.render_local_dir}/setup.sh"
  content         = local.logs_setup_script
  file_permission = "0644"
}

resource "local_file" "metrics_config" {
  count = var.create_metrics && var.render_local_files ? 1 : 0

  filename        = "${path.root}/${var.render_local_dir}/metrics.alloy"
  content         = local.metrics_config
  file_permission = "0644"
}

resource "local_file" "metrics_setup_script" {
  count = var.create_metrics && var.render_local_files ? 1 : 0

  filename        = "${path.root}/${var.render_local_dir}/setup-metrics.sh"
  content         = local.metrics_setup_script
  file_permission = "0644"
}

resource "null_resource" "logs" {
  count = var.create_logs ? 1 : 0

  triggers = {
    ssh_target           = local.ssh_target
    ssh_options          = join("\n", var.ssh_options)
    loki_url             = var.loki_url != null ? var.loki_url : ""
    loki_username        = var.loki_username
    loki_password_sha256 = nonsensitive(sha256(var.loki_password != null ? var.loki_password : ""))
    instance             = var.instance
    platform             = var.platform
    alloy_config_sha256  = sha256(local.logs_config)
    setup_script_sha256  = sha256(local.logs_setup_script)
  }

  lifecycle {
    precondition {
      condition     = local.ssh_target != ""
      error_message = "Either ssh_host_alias or host must be set."
    }
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      OLLY_SSH_TARGET      = self.triggers.ssh_target
      OLLY_SSH_OPTIONS     = self.triggers.ssh_options
      OLLY_LOGS_CONFIG_B64 = base64encode(local.logs_config)
      OLLY_LOGS_SETUP_B64  = base64encode(local.logs_setup_script)
      OLLY_LOKI_USERNAME   = var.loki_username
      OLLY_LOKI_PASSWORD   = var.loki_password != null ? var.loki_password : ""
    }
    command = <<-EOT
      set -euo pipefail

      ssh_options=()
      while IFS= read -r option; do
        [ -n "$option" ] && ssh_options+=("$option")
      done <<< "$OLLY_SSH_OPTIONS"

      ssh_cmd=(ssh "$${ssh_options[@]}" "$OLLY_SSH_TARGET")

      printf '%s' "$OLLY_LOGS_CONFIG_B64" | "$${ssh_cmd[@]}" 'base64 -d > /tmp/olly-logs.alloy'
      printf '%s' "$OLLY_LOGS_SETUP_B64" | "$${ssh_cmd[@]}" 'base64 -d > /tmp/olly-setup.sh'
      {
        printf 'LOKI_USERNAME=%q\n' "$OLLY_LOKI_USERNAME"
        printf 'LOKI_PASSWORD=%q\n' "$OLLY_LOKI_PASSWORD"
      } | "$${ssh_cmd[@]}" 'umask 077; cat > /tmp/olly.env'
      "$${ssh_cmd[@]}" 'chmod 0700 /tmp/olly-setup.sh && chmod 0600 /tmp/olly.env && /tmp/olly-setup.sh'
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    environment = {
      OLLY_SSH_TARGET = try(self.triggers.ssh_target, lookup({
        avalon   = "avalon-yk"
        elysium  = "elysium-yk"
        tirnanog = "tirnanog-yk"
      }, self.triggers.instance, "${self.triggers.ssh_user}@${self.triggers.host}"))
      OLLY_SSH_OPTIONS = try(self.triggers.ssh_options, "-o\nBatchMode=yes")
    }
    command = <<-EOT
      set -euo pipefail

      ssh_options=()
      while IFS= read -r option; do
        [ -n "$option" ] && ssh_options+=("$option")
      done <<< "$OLLY_SSH_OPTIONS"

      ssh "$${ssh_options[@]}" "$OLLY_SSH_TARGET" 'systemctl disable --now alloy-logs >/dev/null 2>&1 || true; systemctl reset-failed alloy-logs >/dev/null 2>&1 || true'
    EOT
  }
}

resource "null_resource" "metrics" {
  count = var.create_metrics ? 1 : 0

  triggers = {
    ssh_target                       = local.ssh_target
    ssh_options                      = join("\n", var.ssh_options)
    instance                         = var.instance
    platform                         = var.platform
    prometheus_remote_write_url      = var.prometheus_remote_write_url != null ? var.prometheus_remote_write_url : ""
    prometheus_username              = var.prometheus_username
    prometheus_password_sha256       = nonsensitive(sha256(var.prometheus_password != null ? var.prometheus_password : ""))
    create_pve_exporter              = tostring(var.create_pve_exporter)
    pve_exporter_token_id            = var.pve_exporter_token_id != null ? var.pve_exporter_token_id : ""
    pve_exporter_token_secret_sha256 = nonsensitive(sha256(var.pve_exporter_token_secret != null ? var.pve_exporter_token_secret : ""))
    pve_exporter_image               = var.pve_exporter_image
    pve_exporter_platform            = var.pve_exporter_platform
    pve_exporter_target              = local.pve_exporter_target
    metrics_config_sha256            = sha256(local.metrics_config)
    setup_script_sha256              = sha256(local.metrics_setup_script)
  }

  lifecycle {
    precondition {
      condition     = local.ssh_target != ""
      error_message = "Either ssh_host_alias or host must be set."
    }

    precondition {
      condition     = !var.create_pve_exporter || local.pve_exporter_target != ""
      error_message = "pve_exporter_target or host must be set when create_pve_exporter is true."
    }
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      OLLY_SSH_TARGET            = self.triggers.ssh_target
      OLLY_SSH_OPTIONS           = self.triggers.ssh_options
      OLLY_METRICS_CONFIG_B64    = base64encode(local.metrics_config)
      OLLY_METRICS_SETUP_B64     = base64encode(local.metrics_setup_script)
      OLLY_PROMETHEUS_PASSWORD   = var.prometheus_password != null ? var.prometheus_password : ""
      OLLY_PVE_EXPORTER_ENABLED  = var.create_pve_exporter ? "true" : "false"
      OLLY_PVE_EXPORTER_USER     = local.pve_exporter_user
      OLLY_PVE_EXPORTER_TOKEN    = local.pve_exporter_token_name
      OLLY_PVE_EXPORTER_SECRET   = var.pve_exporter_token_secret != null ? var.pve_exporter_token_secret : ""
      OLLY_PVE_EXPORTER_IMAGE    = var.pve_exporter_image
      OLLY_PVE_EXPORTER_PLATFORM = var.pve_exporter_platform
      OLLY_PVE_EXPORTER_TARGET   = local.pve_exporter_target
    }
    command = <<-EOT
      set -euo pipefail

      ssh_options=()
      while IFS= read -r option; do
        [ -n "$option" ] && ssh_options+=("$option")
      done <<< "$OLLY_SSH_OPTIONS"

      ssh_cmd=(ssh "$${ssh_options[@]}" "$OLLY_SSH_TARGET")

      printf '%s' "$OLLY_METRICS_CONFIG_B64" | "$${ssh_cmd[@]}" 'base64 -d > /tmp/olly-metrics.alloy'
      printf '%s' "$OLLY_METRICS_SETUP_B64" | "$${ssh_cmd[@]}" 'base64 -d > /tmp/olly-metrics-setup.sh'
      {
        printf 'PROMETHEUS_PASSWORD=%q\n' "$OLLY_PROMETHEUS_PASSWORD"
        printf 'PVE_EXPORTER_ENABLED=%q\n' "$OLLY_PVE_EXPORTER_ENABLED"
        printf 'PVE_EXPORTER_USER=%q\n' "$OLLY_PVE_EXPORTER_USER"
        printf 'PVE_EXPORTER_TOKEN_NAME=%q\n' "$OLLY_PVE_EXPORTER_TOKEN"
        printf 'PVE_EXPORTER_TOKEN_SECRET=%q\n' "$OLLY_PVE_EXPORTER_SECRET"
        printf 'PVE_EXPORTER_IMAGE=%q\n' "$OLLY_PVE_EXPORTER_IMAGE"
        printf 'PVE_EXPORTER_PLATFORM=%q\n' "$OLLY_PVE_EXPORTER_PLATFORM"
        printf 'PVE_EXPORTER_TARGET=%q\n' "$OLLY_PVE_EXPORTER_TARGET"
      } | "$${ssh_cmd[@]}" 'umask 077; cat > /tmp/olly-metrics.env'
      "$${ssh_cmd[@]}" 'chmod 0700 /tmp/olly-metrics-setup.sh && chmod 0600 /tmp/olly-metrics.env && /tmp/olly-metrics-setup.sh'
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    environment = {
      OLLY_SSH_TARGET = try(self.triggers.ssh_target, lookup({
        avalon   = "avalon-yk"
        elysium  = "elysium-yk"
        tirnanog = "tirnanog-yk"
      }, self.triggers.instance, "${self.triggers.ssh_user}@${self.triggers.host}"))
      OLLY_SSH_OPTIONS = try(self.triggers.ssh_options, "-o\nBatchMode=yes")
    }
    command = <<-EOT
      set -euo pipefail

      ssh_options=()
      while IFS= read -r option; do
        [ -n "$option" ] && ssh_options+=("$option")
      done <<< "$OLLY_SSH_OPTIONS"

      ssh "$${ssh_options[@]}" "$OLLY_SSH_TARGET" 'systemctl disable --now alloy-metrics >/dev/null 2>&1 || true; systemctl reset-failed alloy-metrics >/dev/null 2>&1 || true; docker rm -f pve-exporter >/dev/null 2>&1 || true'
    EOT
  }
}
