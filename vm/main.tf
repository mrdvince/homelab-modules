resource "proxmox_virtual_environment_vm" "instance" {
  for_each = {
    for instance in var.instances : instance.vmname => instance
  }

  name                = each.key
  node_name           = var.node_name
  vm_id               = each.value.vmid
  tags                = distinct(concat(var.tags, var.include_vmname_tag ? [each.key] : [], lookup(var.instance_tags, each.key, [])))
  on_boot             = var.on_boot
  machine             = var.machine
  bios                = var.bios
  stop_on_destroy     = var.stop_on_destroy
  reboot_after_update = var.reboot_after_update

  cpu {
    cores   = coalesce(each.value.resources.cores, var.cores)
    flags   = var.cpu_flags
    sockets = coalesce(each.value.resources.sockets, var.sockets)
    type    = coalesce(each.value.resources.cpu_type, var.cpu_type)
  }

  memory {
    dedicated = coalesce(each.value.resources.memory, var.memory)
    floating  = coalesce(each.value.resources.balloon, var.balloon)
  }

  agent {
    enabled = var.agent_enabled
    timeout = var.agent_timeout

    dynamic "wait_for_ip" {
      for_each = var.agent_wait_for_ip_disabled ? [1] : []
      content {
        disabled = true
      }
    }
  }

  network_device {
    bridge      = var.network.bridge
    mac_address = each.value.macaddr
    model       = var.network.model
    firewall    = var.network.firewall
    vlan_id     = var.network.vlan_id
  }

  disk {
    datastore_id      = each.value.disk_path == null ? var.disk.storage : ""
    path_in_datastore = each.value.disk_path
    size              = each.value.disk_path == null ? var.disk.size : null
    interface         = var.disk.interface
    file_format       = each.value.disk_path == null ? var.disk.format : null
    discard           = var.disk.discard
    ssd               = var.disk.ssd
    iothread          = var.disk.iothread
    replicate         = each.value.disk_path == null
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
      cdrom,
      initialization,
      network_device,
    ]
  }
}
