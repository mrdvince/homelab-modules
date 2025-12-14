variable "node_name" {
  description = "Proxmox node to deploy the VM on"
  type        = string
}

variable "instances" {
  description = "List of VM instances to create"
  type = list(object({
    vmname  = string
    vmid    = number
    macaddr = string
  }))
}

variable "tags" {
  description = "Tags for the VM"
  type        = list(string)
  default     = []
}

variable "on_boot" {
  description = "Start VM on boot"
  type        = bool
  default     = true
}

variable "machine" {
  description = "Machine type (pc or q35)"
  type        = string
  default     = "q35"
}

variable "bios" {
  description = "BIOS type (seabios or ovmf)"
  type        = string
  default     = "ovmf"
}

variable "cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 4
}

variable "sockets" {
  description = "Number of CPU sockets"
  type        = number
  default     = 1
}

variable "cpu_type" {
  description = "CPU type"
  type        = string
  default     = "x86-64-v3"
}

variable "memory" {
  description = "Memory in MB"
  type        = number
  default     = 8192
}

variable "balloon" {
  description = "Balloon memory in MB (0 to disable)"
  type        = number
  default     = 0
}

variable "agent_enabled" {
  description = "Enable QEMU guest agent"
  type        = bool
  default     = true
}

variable "agent_timeout" {
  description = "Timeout for QEMU guest agent operations (e.g., '15m' for 15 minutes)"
  type        = string
  default     = "1m"
}

variable "stop_on_destroy" {
  description = "Force stop VM on destroy instead of waiting for graceful shutdown"
  type        = bool
  default     = true
}

variable "os_type" {
  description = "OS type (l26 for Linux 2.6+)"
  type        = string
  default     = "l26"
}

variable "scsi_hardware" {
  description = "SCSI hardware type (virtio-scsi-single enables iothread)"
  type        = string
  default     = "virtio-scsi-single"
}

variable "network" {
  description = "Network device configuration"
  type = object({
    bridge   = string
    model    = optional(string, "virtio")
    firewall = optional(bool, false)
    vlan_id  = optional(number)
  })
}

variable "disk" {
  description = "Primary disk configuration"
  type = object({
    storage   = string
    size      = number
    interface = optional(string, "scsi0")
    format    = optional(string, "raw")
    discard   = optional(string, "on")
    ssd       = optional(bool, false)
    iothread  = optional(bool, true)
  })
}

variable "cdrom" {
  description = "CD-ROM configuration (set iso to 'none' to leave empty)"
  type = object({
    iso       = string
    interface = optional(string, "ide2")
  })
}

variable "efi_disk" {
  description = "EFI disk configuration"
  type = object({
    storage           = string
    type              = optional(string, "4m")
    pre_enrolled_keys = optional(bool, false)
  })
  default = null
}

variable "initialization" {
  description = "Cloud-init configuration"
  type = object({
    datastore_id = string
    ip_config    = optional(string, "dhcp")
    user_account = optional(object({
      username = string
      password = optional(string)
      keys     = optional(list(string))
    }))
  })
  default = null
}
