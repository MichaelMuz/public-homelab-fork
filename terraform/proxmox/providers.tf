terraform {
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.5.0"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.60.0"
    }
  }
}

provider "proxmox" {
  for_each = merge(var.proxmox_cluster, var.decommissioned_nodes)

  alias    = "by-node"
  endpoint = "https://${each.value.ip_address}:8006/"
  insecure = true # our proxmox nodes don't have a cert
  ssh {
    agent    = true
    username = "root"
  }
}

