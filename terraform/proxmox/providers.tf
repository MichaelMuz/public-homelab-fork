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
  alias    = "lab_1"
  endpoint = "https://${local.lab_1_config.ip_address}:8006/"
  insecure = true # our proxmox nodes don't have a cert
  ssh {
    agent    = true
    username = "root"
  }
}

provider "proxmox" {
  alias    = "lab_2"
  endpoint = "https://${local.lab_2_config.ip_address}:8006/"
  insecure = true # our proxmox nodes don't have a cert
  ssh {
    agent    = true
    username = "root"
  }
}
