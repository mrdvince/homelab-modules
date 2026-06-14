variable "name" {
  description = "logical olly unit name; also used as the default remote directory name."
  type        = string
}

variable "host" {
  type    = string
  default = null
}

variable "ssh_host_alias" {
  description = "OpenSSH host alias to use for remote execution. Prefer this for YubiKey-backed ControlMaster sessions."
  type        = string
  default     = null
}

variable "ssh_user" {
  type    = string
  default = "root"
}

variable "ssh_options" {
  description = "Additional OpenSSH arguments used for remote execution."
  type        = list(string)
  default     = ["-o", "BatchMode=yes"]
}

variable "remote_dir" {
  description = "directory on the remote host where unit-owned files are written."
  type        = string
  default     = null
}

variable "render_local_files" {
  type    = bool
  default = true
}

variable "render_local_dir" {
  type    = string
  default = "rendered"
}

variable "files" {
  description = "non-secret files to upload relative to remote_dir and optionally render locally."
  type = map(object({
    content = string
    mode    = optional(string, "0644")
    owner   = optional(string, "root")
    group   = optional(string, "root")
  }))
  default = {}
}

variable "secret_files" {
  description = "secret files to upload relative to remote_dir. these are not rendered locally."
  type = map(object({
    content = string
    mode    = optional(string, "0600")
    owner   = optional(string, "root")
    group   = optional(string, "root")
  }))
  default   = {}
  sensitive = true
}

variable "containers" {
  description = "containers managed by this olly unit."
  type = map(object({
    image          = string
    container_name = optional(string)
    command        = optional(list(string), [])
    platform       = optional(string)
    pull           = optional(bool, true)
    restart        = optional(string, "unless-stopped")
    read_only      = optional(bool, true)
    network_mode   = optional(string)
    pid_mode       = optional(string)
    ports          = optional(list(string), [])
    volumes        = optional(list(string), [])
    env_files      = optional(list(string), [])
    tmpfs          = optional(list(string), [])
    extra_args     = optional(list(string), [])
    extra_hosts    = optional(list(string), [])
    resolve_hosts  = optional(list(string), [])
  }))
  default = {}
}
