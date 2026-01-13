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
          disk_size        = 48
          memory           = 6144
          cpu_cores        = 4
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
    "lab-3" = {
      ip_address = "192.168.1.198"
      k8s_nodes = {
        "talos-worker-03" = {
          ip_address       = "192.168.1.205"
          is_control_plane = false
          disk_size        = 900
          memory           = 9216
          cpu_cores        = 4
        }
      }
    }
    "lab-4" = {
      ip_address = "192.168.1.197"
      k8s_nodes = {
        "talos-worker-04" = {
          ip_address       = "192.168.1.206"
          is_control_plane = false
          disk_size        = 900
          memory           = 9216
          cpu_cores        = 4
        }
      }
    }
    "lab-5" = {
      ip_address = "192.168.1.196"
      k8s_nodes = {
        "talos-cp-03" = {
          ip_address       = "192.168.1.207"
          is_control_plane = true
          disk_size        = 100
          memory           = 3072
          cpu_cores        = 1
        }
        "talos-worker-05" = {
          ip_address       = "192.168.1.208"
          is_control_plane = false
          disk_size        = 800
          memory           = 3072
          cpu_cores        = 3
        }
      }
    }

  }
}

variable "decommissioned_nodes" {
  description = <<-EOT
    Needed because providers must outlive their resources by at least 1 apply cycle.
    This is because you need the provider to exist to destroy its own resources.
    Proxmox nodes being decommissioned. Keep nodes here until all VMs are destroyed.

    Decommission workflow:
    1. Move node from proxmox_cluster to this variable (with empty k8s_nodes)
    2. Run 'tofu apply' to destroy VMs
    3. Remove node from this variable
    4. Run 'tofu apply' to clean up provider
  EOT

  type = map(object({
    ip_address = string
  }))
  default = {}
}
