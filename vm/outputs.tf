output "vm_ids" {
  description = "Map of VM names to VM IDs"
  value = {
    for name, vm in proxmox_virtual_environment_vm.instance : name => vm.vm_id
  }
}

output "vm_ipv4_addresses" {
  description = "Map of VM names to primary IPv4 address"
  value = {
    for name, vm in proxmox_virtual_environment_vm.instance : name => try(
      [for ips in vm.ipv4_addresses : ips[0] if length(ips) > 0 && ips[0] != "127.0.0.1"][0],
      null
    )
  }
}
