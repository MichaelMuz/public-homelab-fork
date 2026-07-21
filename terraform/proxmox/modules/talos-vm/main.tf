resource "proxmox_virtual_environment_vm" "talos_vms" {
  for_each    = var.talos_nodes
  name        = each.key
  description = "Managed by Terraform"
  tags        = ["terraform"]
  node_name   = var.proxmox_node.name
  on_boot     = true

  cpu {
    cores        = each.value.cpu_cores
    type         = "host"
    architecture = "x86_64"
  }

  memory {
    dedicated = each.value.memory
  }

  agent {
    enabled = true
  }

  network_device {
    bridge = "vmbr0"
  }

  disk {
    datastore_id = "local-lvm"
    file_id      = proxmox_virtual_environment_download_file.talos_nocloud_image[local.vm_to_boot_info[each.key].version].id
    file_format  = "raw"
    interface    = "virtio0"
    size         = each.value.boot_disk_size
  }

  dynamic "disk" {
    # Sized volumes carved from the local-lvm thin pool
    for_each = each.value.lvm_disks
    content {
      datastore_id = "local-lvm"
      file_format  = "raw"
      # Interface starts at virtio1 (virtio0 is boot).
      interface = "virtio${disk.key + 1}"
      size      = disk.value.size
    }
  }

  dynamic "disk" {
    for_each = each.value.pass_through_disks
    content {
      # Whole host block devices passed straight through (no datastore, no size).
      datastore_id      = ""
      path_in_datastore = disk.value.by_id_path
      file_format       = "raw"
      # interface is offset past boot + all lvm_disks so the two lists never collide.
      interface = "virtio${disk.key + 1 + length(each.value.lvm_disks)}"
    }
  }

  operating_system {
    type = "l26" # Linux Kernel 2.6 - 5.X.
  }

  initialization {
    datastore_id = "local-lvm"
    # dns {
    #   servers = ["1.1.1.1", "8.8.8.8"] # Consideration for the future instead of relying on hypervisor dns settings
    # }
    ip_config {
      ipv4 {
        address = "${each.value.ip_address}/24"
        gateway = var.default_gateway
      }
      ipv6 {
        address = "dhcp"
      }
    }
  }
}

