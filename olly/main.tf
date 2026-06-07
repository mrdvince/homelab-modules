locals {
  logs_config = templatefile("${path.module}/templates/logs.alloy.tftpl", {
    instance      = var.instance
    platform      = var.platform
    loki_url      = var.loki_url != null ? var.loki_url : ""
    loki_username = var.loki_username
    file_logs     = var.file_logs
  })

  logs_setup_script = file("${path.module}/templates/logs.sh")

  shell_loki_password = replace(var.loki_password != null ? var.loki_password : "", "'", "'\"'\"'")
  shell_loki_username = replace(var.loki_username, "'", "'\"'\"'")
  shell_alloy_image   = replace(var.alloy_image, "'", "'\"'\"'")

  logs_bootstrap_env = <<-EOF
    LOKI_USERNAME='${local.shell_loki_username}'
    LOKI_PASSWORD='${local.shell_loki_password}'
    ALLOY_IMAGE='${local.shell_alloy_image}'
  EOF

  metrics_config = templatefile("${path.module}/templates/metrics.alloy.tftpl", {
    instance                      = var.instance
    platform                      = var.platform
    create_pve_exporter           = var.create_pve_exporter
    create_opnsense_exporter      = var.create_opnsense_exporter
    create_snmp_exporter          = var.create_snmp_exporter
    prometheus_remote_write_url   = var.prometheus_remote_write_url != null ? var.prometheus_remote_write_url : ""
    prometheus_username           = var.prometheus_username
    pve_exporter_target           = local.pve_exporter_target
    opnsense_exporter_listen_port = var.opnsense_exporter_listen_port
    opnsense_exporter_instance    = var.opnsense_instance
    opnsense_exporter_platform    = var.opnsense_platform
    snmp_address                  = var.snmp_address != null ? var.snmp_address : ""
    snmp_instance                 = var.snmp_instance
    snmp_platform                 = var.snmp_platform
  })

  metrics_setup_script = file("${path.module}/templates/metrics.sh")

  pve_token_parts = split("!", var.pve_exporter_token_id != null ? var.pve_exporter_token_id : "!")

  pve_exporter_user       = local.pve_token_parts[0]
  pve_exporter_token_name = local.pve_token_parts[1]

  shell_prometheus_password     = replace(var.prometheus_password != null ? var.prometheus_password : "", "'", "'\"'\"'")
  shell_metrics_alloy_image     = replace(var.alloy_image, "'", "'\"'\"'")
  shell_pve_exporter_user       = replace(local.pve_exporter_user, "'", "'\"'\"'")
  shell_pve_exporter_token_name = replace(local.pve_exporter_token_name, "'", "'\"'\"'")
  shell_pve_exporter_secret     = replace(var.pve_exporter_token_secret != null ? var.pve_exporter_token_secret : "", "'", "'\"'\"'")
  shell_pve_exporter_image      = replace(var.pve_exporter_image, "'", "'\"'\"'")
  shell_pve_exporter_platform   = replace(var.pve_exporter_platform, "'", "'\"'\"'")
  shell_pve_exporter_target     = replace(local.pve_exporter_target, "'", "'\"'\"'")
  shell_opnsense_exporter_image = replace(var.opnsense_exporter_image, "'", "'\"'\"'")
  shell_opnsense_platform       = replace(var.opnsense_exporter_platform, "'", "'\"'\"'")
  shell_opnsense_address        = replace(var.opnsense_address != null ? var.opnsense_address : "", "'", "'\"'\"'")
  shell_opnsense_api_key        = replace(var.opnsense_api_key != null ? var.opnsense_api_key : "", "'", "'\"'\"'")
  shell_opnsense_api_secret     = replace(var.opnsense_api_secret != null ? var.opnsense_api_secret : "", "'", "'\"'\"'")
  shell_opnsense_instance       = replace(var.opnsense_instance, "'", "'\"'\"'")

  metrics_bootstrap_env = <<-EOF
    PROMETHEUS_PASSWORD='${local.shell_prometheus_password}'
    ALLOY_IMAGE='${local.shell_metrics_alloy_image}'
    PVE_EXPORTER_ENABLED='${var.create_pve_exporter ? "true" : "false"}'
    PVE_EXPORTER_USER='${local.shell_pve_exporter_user}'
    PVE_EXPORTER_TOKEN_NAME='${local.shell_pve_exporter_token_name}'
    PVE_EXPORTER_TOKEN_SECRET='${local.shell_pve_exporter_secret}'
    PVE_EXPORTER_IMAGE='${local.shell_pve_exporter_image}'
    PVE_EXPORTER_PLATFORM='${local.shell_pve_exporter_platform}'
    PVE_EXPORTER_TARGET='${local.shell_pve_exporter_target}'
    OPNSENSE_EXPORTER_ENABLED='${var.create_opnsense_exporter ? "true" : "false"}'
    OPNSENSE_EXPORTER_IMAGE='${local.shell_opnsense_exporter_image}'
    OPNSENSE_EXPORTER_PLATFORM='${local.shell_opnsense_platform}'
    OPNSENSE_EXPORTER_LISTEN_PORT='${var.opnsense_exporter_listen_port}'
    OPNSENSE_ADDRESS='${local.shell_opnsense_address}'
    OPNSENSE_API_KEY='${local.shell_opnsense_api_key}'
    OPNSENSE_API_SECRET='${local.shell_opnsense_api_secret}'
    OPNSENSE_INSTANCE='${local.shell_opnsense_instance}'
    OPNSENSE_INSECURE='${var.opnsense_insecure ? "true" : "false"}'
    SNMP_ENABLED='${var.create_snmp_exporter ? "true" : "false"}'
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

  filename        = "${path.root}/${var.render_local_dir}/logs.sh"
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

  filename        = "${path.root}/${var.render_local_dir}/metrics.sh"
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
    alloy_image          = var.alloy_image
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
      OLLY_ALLOY_IMAGE     = var.alloy_image
    }
    command = <<-EOT
      set -euo pipefail

      ssh_options=()
      while IFS= read -r option; do
        [ -n "$option" ] && ssh_options+=("$option")
      done <<< "$OLLY_SSH_OPTIONS"

      ssh_cmd=(ssh "$${ssh_options[@]}" "$OLLY_SSH_TARGET")

      printf '%s' "$OLLY_LOGS_CONFIG_B64" | "$${ssh_cmd[@]}" 'base64 -d > /tmp/olly-logs.alloy'
      printf '%s' "$OLLY_LOGS_SETUP_B64" | "$${ssh_cmd[@]}" 'base64 -d > /tmp/olly-logs.sh'
      {
        printf 'LOKI_USERNAME=%q\n' "$OLLY_LOKI_USERNAME"
        printf 'LOKI_PASSWORD=%q\n' "$OLLY_LOKI_PASSWORD"
        printf 'ALLOY_IMAGE=%q\n' "$OLLY_ALLOY_IMAGE"
      } | "$${ssh_cmd[@]}" 'umask 077; cat > /tmp/olly.env'
      "$${ssh_cmd[@]}" 'chmod 0700 /tmp/olly-logs.sh && chmod 0600 /tmp/olly.env && /tmp/olly-logs.sh'
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

      ssh "$${ssh_options[@]}" "$OLLY_SSH_TARGET" 'docker rm -f alloy-logs >/dev/null 2>&1 || true'
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
    alloy_image                      = var.alloy_image
    prometheus_remote_write_url      = var.prometheus_remote_write_url != null ? var.prometheus_remote_write_url : ""
    prometheus_username              = var.prometheus_username
    prometheus_password_sha256       = nonsensitive(sha256(var.prometheus_password != null ? var.prometheus_password : ""))
    create_pve_exporter              = tostring(var.create_pve_exporter)
    pve_exporter_token_id            = var.pve_exporter_token_id != null ? var.pve_exporter_token_id : ""
    pve_exporter_token_secret_sha256 = nonsensitive(sha256(var.pve_exporter_token_secret != null ? var.pve_exporter_token_secret : ""))
    pve_exporter_image               = var.pve_exporter_image
    pve_exporter_platform            = var.pve_exporter_platform
    pve_exporter_target              = local.pve_exporter_target
    create_opnsense_exporter         = tostring(var.create_opnsense_exporter)
    opnsense_exporter_image          = var.opnsense_exporter_image
    opnsense_exporter_platform       = var.opnsense_exporter_platform
    opnsense_exporter_listen_port    = tostring(var.opnsense_exporter_listen_port)
    opnsense_address                 = var.opnsense_address != null ? var.opnsense_address : ""
    opnsense_api_key_sha256          = nonsensitive(sha256(var.opnsense_api_key != null ? var.opnsense_api_key : ""))
    opnsense_api_secret_sha256       = nonsensitive(sha256(var.opnsense_api_secret != null ? var.opnsense_api_secret : ""))
    opnsense_instance                = var.opnsense_instance
    opnsense_platform                = var.opnsense_platform
    opnsense_insecure                = tostring(var.opnsense_insecure)
    create_snmp_exporter             = tostring(var.create_snmp_exporter)
    snmp_address                     = var.snmp_address != null ? var.snmp_address : ""
    snmp_username                    = var.snmp_username
    snmp_password_sha256             = nonsensitive(sha256(var.snmp_password != null ? var.snmp_password : ""))
    snmp_enc_key_sha256              = nonsensitive(sha256(var.snmp_enc_key != null ? var.snmp_enc_key : ""))
    snmp_instance                    = var.snmp_instance
    snmp_platform                    = var.snmp_platform
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

    precondition {
      condition     = !var.create_opnsense_exporter || var.opnsense_address != null
      error_message = "opnsense_address must be set when create_opnsense_exporter is true."
    }

    precondition {
      condition     = !var.create_snmp_exporter || var.snmp_address != null
      error_message = "snmp_address must be set when create_snmp_exporter is true."
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
      OLLY_ALLOY_IMAGE           = var.alloy_image
      OLLY_PVE_EXPORTER_ENABLED  = var.create_pve_exporter ? "true" : "false"
      OLLY_PVE_EXPORTER_USER     = local.pve_exporter_user
      OLLY_PVE_EXPORTER_TOKEN    = local.pve_exporter_token_name
      OLLY_PVE_EXPORTER_SECRET   = var.pve_exporter_token_secret != null ? var.pve_exporter_token_secret : ""
      OLLY_PVE_EXPORTER_IMAGE    = var.pve_exporter_image
      OLLY_PVE_EXPORTER_PLATFORM = var.pve_exporter_platform
      OLLY_PVE_EXPORTER_TARGET   = local.pve_exporter_target
      OLLY_OPNSENSE_ENABLED      = var.create_opnsense_exporter ? "true" : "false"
      OLLY_OPNSENSE_IMAGE        = var.opnsense_exporter_image
      OLLY_OPNSENSE_PLATFORM     = var.opnsense_exporter_platform
      OLLY_OPNSENSE_LISTEN_PORT  = tostring(var.opnsense_exporter_listen_port)
      OLLY_OPNSENSE_ADDRESS      = var.opnsense_address != null ? var.opnsense_address : ""
      OLLY_OPNSENSE_API_KEY      = var.opnsense_api_key != null ? var.opnsense_api_key : ""
      OLLY_OPNSENSE_API_SECRET   = var.opnsense_api_secret != null ? var.opnsense_api_secret : ""
      OLLY_OPNSENSE_INSTANCE     = var.opnsense_instance
      OLLY_OPNSENSE_INSECURE     = var.opnsense_insecure ? "true" : "false"
      OLLY_SNMP_USERNAME         = var.snmp_username
      OLLY_SNMP_PASSWORD         = var.snmp_password != null ? var.snmp_password : ""
      OLLY_SNMP_ENC_KEY          = var.snmp_enc_key != null ? var.snmp_enc_key : ""
    }
    command = <<-EOT
      set -euo pipefail

      ssh_options=()
      while IFS= read -r option; do
        [ -n "$option" ] && ssh_options+=("$option")
      done <<< "$OLLY_SSH_OPTIONS"

      ssh_cmd=(ssh "$${ssh_options[@]}" "$OLLY_SSH_TARGET")

      printf '%s' "$OLLY_METRICS_CONFIG_B64" | "$${ssh_cmd[@]}" 'base64 -d > /tmp/olly-metrics.alloy'
      printf '%s' "$OLLY_METRICS_SETUP_B64" | "$${ssh_cmd[@]}" 'base64 -d > /tmp/olly-metrics.sh'
      {
        printf 'PROMETHEUS_PASSWORD=%q\n' "$OLLY_PROMETHEUS_PASSWORD"
        printf 'ALLOY_IMAGE=%q\n' "$OLLY_ALLOY_IMAGE"
        printf 'PVE_EXPORTER_ENABLED=%q\n' "$OLLY_PVE_EXPORTER_ENABLED"
        printf 'PVE_EXPORTER_USER=%q\n' "$OLLY_PVE_EXPORTER_USER"
        printf 'PVE_EXPORTER_TOKEN_NAME=%q\n' "$OLLY_PVE_EXPORTER_TOKEN"
        printf 'PVE_EXPORTER_TOKEN_SECRET=%q\n' "$OLLY_PVE_EXPORTER_SECRET"
        printf 'PVE_EXPORTER_IMAGE=%q\n' "$OLLY_PVE_EXPORTER_IMAGE"
        printf 'PVE_EXPORTER_PLATFORM=%q\n' "$OLLY_PVE_EXPORTER_PLATFORM"
        printf 'PVE_EXPORTER_TARGET=%q\n' "$OLLY_PVE_EXPORTER_TARGET"
        printf 'OPNSENSE_EXPORTER_ENABLED=%q\n' "$OLLY_OPNSENSE_ENABLED"
        printf 'OPNSENSE_EXPORTER_IMAGE=%q\n' "$OLLY_OPNSENSE_IMAGE"
        printf 'OPNSENSE_EXPORTER_PLATFORM=%q\n' "$OLLY_OPNSENSE_PLATFORM"
        printf 'OPNSENSE_EXPORTER_LISTEN_PORT=%q\n' "$OLLY_OPNSENSE_LISTEN_PORT"
        printf 'OPNSENSE_ADDRESS=%q\n' "$OLLY_OPNSENSE_ADDRESS"
        printf 'OPNSENSE_API_KEY=%q\n' "$OLLY_OPNSENSE_API_KEY"
        printf 'OPNSENSE_API_SECRET=%q\n' "$OLLY_OPNSENSE_API_SECRET"
        printf 'OPNSENSE_INSTANCE=%q\n' "$OLLY_OPNSENSE_INSTANCE"
        printf 'OPNSENSE_INSECURE=%q\n' "$OLLY_OPNSENSE_INSECURE"
        printf 'SNMP_ENABLED=%q\n' "${var.create_snmp_exporter ? "true" : "false"}"
        printf 'SNMP_USERNAME=%q\n' "$OLLY_SNMP_USERNAME"
        printf 'SNMP_PASSWORD=%q\n' "$OLLY_SNMP_PASSWORD"
        printf 'SNMP_ENC_KEY=%q\n' "$OLLY_SNMP_ENC_KEY"
      } | "$${ssh_cmd[@]}" 'umask 077; cat > /tmp/olly-metrics.env'
      "$${ssh_cmd[@]}" 'chmod 0700 /tmp/olly-metrics.sh && chmod 0600 /tmp/olly-metrics.env && /tmp/olly-metrics.sh'
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

      ssh "$${ssh_options[@]}" "$OLLY_SSH_TARGET" 'docker rm -f alloy-metrics pve-exporter opnsense-exporter >/dev/null 2>&1 || true'
    EOT
  }
}
