resource "proxmox_virtual_environment_vm" "talos_vms" {
  for_each    = var.talos_nodes
  name        = each.key
  description = "Managed by Terraform"
  tags        = ["terraform"]
  node_name   = var.proxmox_node.name
  on_boot     = true

  cpu {
    cores = each.value.cpu_cores
    type  = "x86-64-v2-AES"
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
    file_id      = proxmox_virtual_environment_download_file.talos_nocloud_image.id
    file_format  = "raw"
    interface    = "virtio0"
    size         = each.value.disk_size
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

