locals {
  mac_suffix     = join(":", regexall("..", substr(md5(var.hostname), 0, 6)))
  management_mac = "52:54:00:${local.mac_suffix}"
  external_mac   = "52:54:01:${local.mac_suffix}"
  external_cidr  = "${cidrhost(var.netstack_cidr, 0)}/24"
  external_ip    = cidrhost(local.external_cidr, 254)
}

resource "libvirt_pool" "pool" {
  name = "${var.hostname}-pool"
  type = "dir"
  target = {
    path = coalesce(var.pool_path, "/var/lib/libvirt/images/${var.hostname}")
  }
}

resource "libvirt_network" "netstack" {
  count     = var.enable_netstack ? 1 : 0
  name      = "${var.hostname}-netstack"
  autostart = true

  ips = [{
    address = local.external_ip
    prefix  = 24
  }]
}

resource "libvirt_volume" "os_image" {
  name   = "rocky-9-base.qcow2"
  pool   = libvirt_pool.pool.name
  target = { format = { type = "qcow2" } }
  create = { content = { url = var.rocky_image } }
}

resource "libvirt_volume" "disk" {
  name       = "${var.hostname}.qcow2"
  pool       = libvirt_pool.pool.name
  capacity   = var.disk_size_gib * 1024 * 1024 * 1024
  allocation = 0
  target     = { format = { type = "qcow2" } }
  backing_store = {
    path   = libvirt_volume.os_image.path
    format = { type = "qcow2" }
  }

  lifecycle {
    ignore_changes = [allocation]
  }
}

resource "libvirt_cloudinit_disk" "commoninit" {
  name      = "${var.hostname}-commoninit"
  meta_data = yamlencode({ instance-id = var.hostname, local-hostname = var.hostname })
  user_data = templatefile("${path.module}/config/cloud_init.cfg", {
    hostname   = var.hostname
    public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
  })
  network_config = templatefile("${path.module}/config/network_config.cfg", {
    management_mac   = local.management_mac
    external_mac     = local.external_mac
    netstack_enabled = var.enable_netstack
  })
}

resource "libvirt_volume" "cloudinit" {
  name   = "${var.hostname}-${substr(libvirt_cloudinit_disk.commoninit.id, 0, 12)}.iso"
  pool   = libvirt_pool.pool.name
  target = { format = { type = "raw" } }
  create = { content = { url = libvirt_cloudinit_disk.commoninit.path } }

  lifecycle {
    create_before_destroy = true
    # libvirt detecta ISO9660 tras la carga, aunque se cree como raw.
    ignore_changes = [target]
  }
}

resource "libvirt_domain" "rockystack" {
  name        = var.hostname
  type        = "kvm"
  running     = true
  memory      = var.memory_mb
  memory_unit = "MiB"
  vcpu        = var.cpu
  cpu         = { mode = "host-passthrough" }
  features    = { acpi = true, apic = {} }

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    firmware     = "efi"
    boot_devices = [{ dev = "hd" }]
  }

  devices = {
    disks = [
      {
        source = { file = { file = libvirt_volume.disk.path } }
        target = { dev = "vda", bus = "virtio" }
        driver = { name = "qemu", type = "qcow2", cache = "writeback" }
      },
      {
        source    = { file = { file = libvirt_volume.cloudinit.path } }
        target    = { dev = "vdb", bus = "virtio" }
        driver    = { name = "qemu", type = "raw" }
        read_only = true
      }
    ]

    interfaces = concat([{
      type        = "network"
      mac         = { address = local.management_mac }
      model       = { type = "virtio" }
      source      = { network = { network = var.management_network } }
      wait_for_ip = { source = "lease", network = "0.0.0.0/0" }
      }], var.enable_netstack ? [{
      type   = "network"
      mac    = { address = local.external_mac }
      model  = { type = "virtio" }
      source = { network = { network = libvirt_network.netstack[0].name } }
    }] : [])

    consoles = [{ type = "pty", target = { type = "serial", port = 0 } }]
  }
}

data "libvirt_domain_interface_addresses" "rockystack" {
  domain = libvirt_domain.rockystack.name
  source = "lease"
}
