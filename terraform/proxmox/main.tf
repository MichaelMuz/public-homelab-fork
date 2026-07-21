module "vms" {
  for_each = var.proxmox_cluster

  source = "./modules/talos-vm"
  providers = {
    proxmox = proxmox.by-node[each.key]
  }
  proxmox_node = {
    name = each.key
    ip   = each.value.ip_address
  }
  talos_nodes = {
    for node_name, node_config in each.value.k8s_nodes : node_name => {
      ip_address         = node_config.ip_address
      boot_disk_size     = node_config.boot_disk_size
      memory             = node_config.memory
      cpu_cores          = node_config.cpu_cores
      boot_image_url     = node_config.boot_image_url
      lvm_disks          = node_config.lvm_disks
      pass_through_disks = node_config.pass_through_disks
    }
  }
}

