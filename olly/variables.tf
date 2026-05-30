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

variable "loki_url" {
  type = string
}

variable "loki_username" {
  type    = string
  default = "alloy"
}

variable "loki_password" {
  type      = string
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
  ]
}
