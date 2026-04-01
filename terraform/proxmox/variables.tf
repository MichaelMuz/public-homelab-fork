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
      boot_image_url   = string
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
          boot_image_url   = "https://factory.talos.dev/image/787b79bb847a07ebb9ae37396d015617266b1cef861107eaec85968ad7b40618/v1.7.4/nocloud-amd64.raw.gz"
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
          boot_image_url   = "https://factory.talos.dev/image/787b79bb847a07ebb9ae37396d015617266b1cef861107eaec85968ad7b40618/v1.7.4/nocloud-amd64.raw.gz"
        }
        "talos-worker-02" = {
          ip_address       = "192.168.1.204"
          is_control_plane = false
          disk_size        = 300
          memory           = 8192
          cpu_cores        = 5
          boot_image_url   = "https://factory.talos.dev/image/787b79bb847a07ebb9ae37396d015617266b1cef861107eaec85968ad7b40618/v1.7.4/nocloud-amd64.raw.gz"
        }
      }
    }
    "lab-3" = {
      ip_address = "192.168.1.198"
      k8s_nodes = {
        "talos-worker-03" = {
          ip_address       = "192.168.1.205"
          is_control_plane = false
          disk_size        = 750
          memory           = 6144
          cpu_cores        = 4
          # cloud factory only advertises .raw.xz but people just replace .xz with .gz https://forum.proxmox.com/threads/cloud-init-using-a-raw-xz-file.158782/
          boot_image_url   = "https://factory.talos.dev/image/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b/v1.12.6/nocloud-amd64.raw.gz"
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
          memory           = 14336
          cpu_cores        = 4
          boot_image_url   = "https://factory.talos.dev/image/787b79bb847a07ebb9ae37396d015617266b1cef861107eaec85968ad7b40618/v1.7.4/nocloud-amd64.raw.gz"
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
          boot_image_url   = "https://factory.talos.dev/image/787b79bb847a07ebb9ae37396d015617266b1cef861107eaec85968ad7b40618/v1.7.4/nocloud-amd64.raw.gz"
        }
        "talos-worker-05" = {
          ip_address       = "192.168.1.208"
          is_control_plane = false
          disk_size        = 800
          memory           = 3072
          cpu_cores        = 3
          boot_image_url   = "https://factory.talos.dev/image/787b79bb847a07ebb9ae37396d015617266b1cef861107eaec85968ad7b40618/v1.7.4/nocloud-amd64.raw.gz"
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
