variable "host" {
  type = string
}

variable "ssh_user" {
  type    = string
  default = "root"
}

variable "ssh_private_key_path" {
  type = string
}

variable "create_logs" {
  type    = bool
  default = false
}

variable "create_metrics" {
  type    = bool
  default = false
}

variable "create_pve_exporter" {
  type    = bool
  default = false
}

variable "loki_url" {
  type    = string
  default = null
}

variable "loki_username" {
  type    = string
  default = "alloy"
}

variable "loki_password" {
  type      = string
  default   = null
  sensitive = true
}

variable "instance" {
  type = string
}

variable "platform" {
  type    = string
  default = "proxmox"
}

variable "render_local_files" {
  type    = bool
  default = true
}

variable "render_local_dir" {
  type    = string
  default = "rendered"
}

variable "file_logs" {
  type = list(object({
    path     = string
    job      = optional(string, "proxmox-file")
    log_file = string
  }))

  default = [
    {
      path     = "/var/log/pve/tasks/index*"
      log_file = "pve-task-index"
    },
    {
      path     = "/var/log/pve/tasks/active"
      log_file = "pve-task-active"
    },
    {
      path     = "/var/log/pve-firewall.log"
      log_file = "pve-firewall"
    },
    {
      path     = "/var/log/pveproxy/access.log"
      log_file = "pveproxy-access"
    },
    {
      path     = "/var/log/apt/history.log"
      log_file = "apt-history"
    },
    {
      path     = "/var/log/dpkg.log"
      log_file = "dpkg"
    },
    {
      path     = "/var/log/auth.log"
      log_file = "auth"
    },
    {
      path     = "/var/log/syslog"
      log_file = "syslog"
    },
    {
      path     = "/var/log/kern.log"
      log_file = "kernel"
    },
    {
      path     = "/var/lib/docker/containers/*/*.log"
      log_file = "docker"
      job      = "docker-file"
    },
  ]
}

variable "prometheus_remote_write_url" {
  type    = string
  default = null
}

variable "prometheus_username" {
  type    = string
  default = "alloy"
}

variable "prometheus_password" {
  type      = string
  default   = null
  sensitive = true
}

variable "pve_exporter_token_id" {
  type    = string
  default = null
}

variable "pve_exporter_token_secret" {
  type      = string
  default   = null
  sensitive = true
}

variable "pve_exporter_image" {
  type    = string
  default = "prompve/prometheus-pve-exporter:latest"
}

variable "pve_exporter_platform" {
  type    = string
  default = "linux/amd64"
}

variable "pve_exporter_target" {
  type    = string
  default = null
}
