locals {
  all_k8s_nodes = merge([
    for proxmox_node_name, proxmox_config in var.proxmox_cluster :
    proxmox_config.k8s_nodes
  ]...)

  worker_nodes = {
    for name, config in local.all_k8s_nodes : name => config
    if !config.is_control_plane
  }

  control_plane_nodes = {
    for name, config in local.all_k8s_nodes : name => config
    if config.is_control_plane
  }

  control_plane_node_ips = [for cp_node in local.control_plane_nodes : cp_node.ip_address]
  worker_node_ips        = [for worker_node in local.worker_nodes : worker_node.ip_address]

  bootstrap_node_name        = keys(local.control_plane_nodes)[0]
  bootstrap_node             = local.control_plane_nodes[local.bootstrap_node_name]
  cluster_bootstrap_endpoint = "https://${local.bootstrap_node.ip_address}:6443"
}
