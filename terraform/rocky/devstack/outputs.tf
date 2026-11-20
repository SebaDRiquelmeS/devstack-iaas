locals {
  management_ip = one(flatten([
    for interface in data.libvirt_domain_interface_addresses.rockystack.interfaces : [
      for address in interface.addrs : address.addr if address.type == "ipv4"
    ] if lower(interface.hwaddr) == local.management_mac
  ]))
}

output "horizon_url" {
  description = "Dirección del panel cuando termine Ansible."
  value       = "http://${local.management_ip}/dashboard/"
}

output "ansible_inventory" {
  description = "Inventario YAML para los playbooks de Rocky."
  value = yamlencode({
    all = { children = { devstack = { hosts = {
      (var.hostname) = merge({
        ansible_host               = local.management_ip
        ansible_user               = "rocky"
        ansible_python_interpreter = "/usr/bin/python3"
        ansible_ssh_common_args    = "-o StrictHostKeyChecking=accept-new"
        devstack_host_ip           = local.management_ip
        }, var.enable_netstack ? {
        devstack_public_interface = "devstack-ext"
        devstack_floating_range   = local.external_cidr
        devstack_public_gateway   = local.external_ip
      } : {})
    } } } }
  })
}
