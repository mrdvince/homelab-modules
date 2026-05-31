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
    pve_exporter_target         = var.pve_exporter_target != null ? var.pve_exporter_target : var.host
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

  metrics_bootstrap_env = <<-EOF
    PROMETHEUS_PASSWORD='${local.shell_prometheus_password}'
    PVE_EXPORTER_ENABLED='${var.create_pve_exporter ? "true" : "false"}'
    PVE_EXPORTER_USER='${local.shell_pve_exporter_user}'
    PVE_EXPORTER_TOKEN_NAME='${local.shell_pve_exporter_token_name}'
    PVE_EXPORTER_TOKEN_SECRET='${local.shell_pve_exporter_secret}'
    PVE_EXPORTER_IMAGE='${local.shell_pve_exporter_image}'
    PVE_EXPORTER_PLATFORM='${local.shell_pve_exporter_platform}'
  EOF
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
    host                 = var.host
    ssh_user             = var.ssh_user
    ssh_private_key_path = var.ssh_private_key_path
    loki_url             = var.loki_url != null ? var.loki_url : ""
    loki_username        = var.loki_username
    loki_password_sha256 = nonsensitive(sha256(var.loki_password != null ? var.loki_password : ""))
    instance             = var.instance
    platform             = var.platform
    alloy_config_sha256  = sha256(local.logs_config)
    setup_script_sha256  = sha256(local.logs_setup_script)
  }

  connection {
    type        = "ssh"
    host        = self.triggers.host
    user        = self.triggers.ssh_user
    private_key = file(self.triggers.ssh_private_key_path)
  }

  provisioner "file" {
    content     = local.logs_config
    destination = "/tmp/olly-logs.alloy"
  }

  provisioner "file" {
    content     = local.logs_setup_script
    destination = "/tmp/olly-setup.sh"
  }

  provisioner "file" {
    content     = local.logs_bootstrap_env
    destination = "/tmp/olly.env"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 0700 /tmp/olly-setup.sh",
      "chmod 0600 /tmp/olly.env",
      "/tmp/olly-setup.sh",
    ]
  }

  provisioner "remote-exec" {
    when = destroy

    connection {
      type        = "ssh"
      host        = self.triggers.host
      user        = self.triggers.ssh_user
      private_key = file(self.triggers.ssh_private_key_path)
    }

    inline = [
      "systemctl disable --now alloy-logs >/dev/null 2>&1 || true",
      "systemctl reset-failed alloy-logs >/dev/null 2>&1 || true",
    ]
  }
}

resource "null_resource" "metrics" {
  count = var.create_metrics ? 1 : 0

  triggers = {
    host                             = var.host
    ssh_user                         = var.ssh_user
    ssh_private_key_path             = var.ssh_private_key_path
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
    pve_exporter_target              = var.pve_exporter_target != null ? var.pve_exporter_target : var.host
    metrics_config_sha256            = sha256(local.metrics_config)
    setup_script_sha256              = sha256(local.metrics_setup_script)
  }

  connection {
    type        = "ssh"
    host        = self.triggers.host
    user        = self.triggers.ssh_user
    private_key = file(self.triggers.ssh_private_key_path)
  }

  provisioner "file" {
    content     = local.metrics_config
    destination = "/tmp/olly-metrics.alloy"
  }

  provisioner "file" {
    content     = local.metrics_setup_script
    destination = "/tmp/olly-metrics-setup.sh"
  }

  provisioner "file" {
    content     = local.metrics_bootstrap_env
    destination = "/tmp/olly-metrics.env"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 0700 /tmp/olly-metrics-setup.sh",
      "chmod 0600 /tmp/olly-metrics.env",
      "/tmp/olly-metrics-setup.sh",
    ]
  }

  provisioner "remote-exec" {
    when = destroy

    connection {
      type        = "ssh"
      host        = self.triggers.host
      user        = self.triggers.ssh_user
      private_key = file(self.triggers.ssh_private_key_path)
    }

    inline = [
      "systemctl disable --now alloy-metrics >/dev/null 2>&1 || true",
      "systemctl reset-failed alloy-metrics >/dev/null 2>&1 || true",
      "docker rm -f pve-exporter >/dev/null 2>&1 || true",
    ]
  }
}
