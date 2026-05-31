variable "template_name" {
  description = "Name of the template"
  type        = string
  default     = null
}

variable "pm_api_url" {
  description = "Proxmox API endpoint"
  type        = string
}

variable "pm_api_token_id" {
  description = "Proxmox API token id"
  type        = string
  sensitive   = true
}

variable "pm_api_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
}

variable "pm_tls_insecure" {
  description = "Skip TLS verification for the Proxmox API"
  type        = bool
  default     = false
}

variable "os_type" {
  description = "Type of the OS"
  type        = string
}

variable "target_node" {
  description = "Node to deploy the VM to"
  type        = string
}

variable "vmid" {
  description = "VM ID"
  type        = number
  default     = 0
}

variable "tags" {
  description = "Tags for the VM"
  default     = null
}

variable "vm_base_config_map" {
  description = "Base VM configuration options"
  type        = map(any)
  default     = {}
}

variable "vm_config_map" {
  type        = map(any)
  description = "Additional VM configuration options"
  # bios type can seabios or ovmf
}

variable "sshkeys" {
  description = "SSH keys used in the VM"
  default     = null
}

variable "cipassword" {
  description = "Password for the VM"
  type        = string
  default     = null
}

variable "network" {
  description = "VM Network configuration"
  type        = map(any)
}

variable "serial" {
  description = "VM Serial configuration"
  type        = map(any)
}

variable "efidisk" {
  description = "EFI Disk config"
  type        = map(any)
  default     = null
}

variable "instances" {
  description = "VM instances"
  type = list(object({
    vmname   = string,
    vmid     = number,
    ipconfig = string,
    macaddr  = string
  }))
}

variable "disk_configurations" {
  type = map(any)
}
