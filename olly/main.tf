locals {
  alloy_config = templatefile("${path.module}/templates/config.alloy.tftpl", {
    instance      = var.instance
    platform      = var.platform
    loki_url      = var.loki_url
    loki_username = var.loki_username
    file_logs     = var.file_logs
  })

  setup_script = file("${path.module}/templates/setup.sh")

  shell_loki_password = replace(var.loki_password, "'", "'\"'\"'")
  shell_loki_username = replace(var.loki_username, "'", "'\"'\"'")

  bootstrap_env = <<-EOF
    LOKI_USERNAME='${local.shell_loki_username}'
    LOKI_PASSWORD='${local.shell_loki_password}'
  EOF
}

resource "local_file" "alloy_config" {
  count = var.render_local_files ? 1 : 0

  filename        = "${path.root}/${var.render_local_dir}/config.alloy"
  content         = local.alloy_config
  file_permission = "0644"
}

resource "local_file" "setup_script" {
  count = var.render_local_files ? 1 : 0

  filename        = "${path.root}/${var.render_local_dir}/setup.sh"
  content         = local.setup_script
  file_permission = "0644"
}

resource "null_resource" "apply" {
  triggers = {
    host                 = var.host
    ssh_user             = var.ssh_user
    ssh_private_key_path = var.ssh_private_key_path
    loki_url             = var.loki_url
    loki_username        = var.loki_username
    loki_password_sha256 = nonsensitive(sha256(var.loki_password))
    instance             = var.instance
    platform             = var.platform
    alloy_config_sha256  = sha256(local.alloy_config)
    setup_script_sha256  = sha256(local.setup_script)
  }

  connection {
    type        = "ssh"
    host        = var.host
    user        = var.ssh_user
    private_key = file(var.ssh_private_key_path)
  }

  provisioner "file" {
    content     = local.alloy_config
    destination = "/tmp/olly-config.alloy"
  }

  provisioner "file" {
    content     = local.setup_script
    destination = "/tmp/olly-setup.sh"
  }

  provisioner "file" {
    content     = local.bootstrap_env
    destination = "/tmp/olly.env"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 0700 /tmp/olly-setup.sh",
      "chmod 0600 /tmp/olly.env",
      "/tmp/olly-setup.sh",
    ]
  }
}
