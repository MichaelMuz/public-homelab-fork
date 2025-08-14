variable "cluster_name" {
  type    = string
  default = "homelab"
}

variable "proxmox_cluster" {
  description = "Proxmox nodes and the Kubernetes nodes they host"
  type = map(object({
    ip_address = string
    k8s_nodes = map(object({
      ip_address       = string
      is_control_plane = bool
      disk_size        = number
      memory           = number
      cpu_cores        = number
    }))
  }))
  default = {
    "lab-1" = {
      ip_address = "192.168.1.200"
      k8s_nodes = {
        "talos-cp-01" = {
          ip_address       = "192.168.1.201"
          is_control_plane = true
          disk_size        = 20
          memory           = 3072
          cpu_cores        = 2
        }
        "talos-worker-01" = {
          ip_address       = "192.168.1.202"
          is_control_plane = false
          disk_size        = 28
          memory           = 3072
          cpu_cores        = 2
        }
      }
    }
    "lab-2" = {
      ip_address = "192.168.1.199"
      k8s_nodes = {
        "talos-cp-02" = {
          ip_address       = "192.168.1.203"
          is_control_plane = true
          disk_size        = 37
          memory           = 4096
          cpu_cores        = 3
        }
        "talos-worker-02" = {
          ip_address       = "192.168.1.204"
          is_control_plane = false
          disk_size        = 300
          memory           = 8192
          cpu_cores        = 5
        }
      }
    }
  }
}
