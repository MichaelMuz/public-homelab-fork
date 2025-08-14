# NOTICE: This should be a beautiful for_each loop over var.proxmox_cluster
# but Terraform doesn't support dynamic provider selection in for_each.
# When they fix this limitation, we can replace these duplicate module
# calls with:
#
# module "vms" {
#   for_each = var.proxmox_cluster
#   providers = {
#     proxmox = proxmox[each.key]  # This doesn't work yet
#   }
#   # ... rest of config
# }
#
# Until then, we're stuck with manual duplication. SAD!

module "lab_1_vms" {
  source = "./modules/talos-vm"
  providers = {
    proxmox = proxmox.lab_1
  }
  proxmox_node = {
    name = "lab-1"
    ip   = local.lab_1_config.ip_address
  }
  talos_nodes = {
    for node_name, node_config in local.lab_1_config.k8s_nodes : node_name => {
      ip_address = node_config.ip_address
      disk_size  = node_config.disk_size
      memory     = node_config.memory
      cpu_cores  = node_config.cpu_cores
    }
  }
}

module "lab_2_vms" {
  source = "./modules/talos-vm"
  providers = {
    proxmox = proxmox.lab_2
  }
  proxmox_node = {
    name = "lab-2"
    ip   = local.lab_2_config.ip_address
  }
  talos_nodes = {
    for node_name, node_config in local.lab_2_config.k8s_nodes : node_name => {
      ip_address = node_config.ip_address
      disk_size  = node_config.disk_size
      memory     = node_config.memory
      cpu_cores  = node_config.cpu_cores
    }
  }
}
