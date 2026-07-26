locals {
  instance_ipv4_addresses = {
    for instance in var.instances : instance.vmname => instance.ipv4_address
  }
}

output "vm_ids" {
  description = "Map of VM names to VM IDs"
  value = {
    for name, vm in proxmox_virtual_environment_vm.instance : name => vm.vm_id
  }
}

output "vm_mac_addresses" {
  description = "Map of VM names to MAC addresses"
  value = {
    for instance in var.instances : instance.vmname => instance.macaddr
  }
}

output "vm_ipv4_addresses" {
  description = "Map of VM names to primary IPv4 address"
  value = {
    for name, vm in proxmox_virtual_environment_vm.instance : name => (
      local.instance_ipv4_addresses[name] != null
      ? local.instance_ipv4_addresses[name]
      : try(
        [for ips in vm.ipv4_addresses : ips[0] if length(ips) > 0 && ips[0] != "127.0.0.1"][0],
        null
      )
    )
  }
}
