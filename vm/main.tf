resource "proxmox_virtual_environment_vm" "instance" {
  for_each = {
    for instance in var.instances : instance.vmname => instance
  }

  name            = each.key
  node_name       = var.node_name
  vm_id           = each.value.vmid
  tags            = var.tags
  on_boot         = var.on_boot
  machine         = var.machine
  bios            = var.bios
  stop_on_destroy = var.stop_on_destroy

  cpu {
    cores   = var.cores
    sockets = var.sockets
    type    = var.cpu_type
  }

  memory {
    dedicated = var.memory
    floating  = var.balloon
  }

  agent {
    enabled = var.agent_enabled
    timeout = var.agent_timeout
  }

  network_device {
    bridge      = var.network.bridge
    mac_address = each.value.macaddr
    model       = var.network.model
    firewall    = var.network.firewall
    vlan_id     = var.network.vlan_id
  }

  disk {
    datastore_id = var.disk.storage
    size         = var.disk.size
    interface    = var.disk.interface
    file_format  = var.disk.format
    discard      = var.disk.discard
    ssd          = var.disk.ssd
    iothread     = var.disk.iothread
  }

  cdrom {
    file_id   = var.cdrom.iso
    interface = var.cdrom.interface
  }

  dynamic "efi_disk" {
    for_each = var.efi_disk != null ? [1] : []
    content {
      datastore_id      = var.efi_disk.storage
      type              = var.efi_disk.type
      pre_enrolled_keys = var.efi_disk.pre_enrolled_keys
    }
  }

  dynamic "initialization" {
    for_each = var.initialization != null ? [1] : []
    content {
      datastore_id = var.initialization.datastore_id

      ip_config {
        ipv4 {
          address = var.initialization.ip_config
        }
      }

      dynamic "user_account" {
        for_each = var.initialization.user_account != null ? [1] : []
        content {
          username = var.initialization.user_account.username
          password = var.initialization.user_account.password
          keys     = var.initialization.user_account.keys
        }
      }
    }
  }

  scsi_hardware = var.scsi_hardware

  operating_system {
    type = var.os_type
  }

  serial_device {}

  lifecycle {
    ignore_changes = [
      initialization,
      network_device,
    ]
  }
}
