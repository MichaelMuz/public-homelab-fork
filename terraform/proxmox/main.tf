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
      ip_address = node_config.ip_address
      disk_size  = node_config.disk_size
      memory     = node_config.memory
      cpu_cores  = node_config.cpu_cores
    }
  }
}

