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
      # Boot disk size in GB. Still per-node because the unmigrated "fused" nodes use a large boot
      # disk as their Longhorn storage, and bpg can't shrink a disk. Once every node is on split
      # storage (small boot + lvm/passthrough disks) this collapses to a single shared default.
      boot_disk_size     = number
      memory             = number
      cpu_cores          = number
      boot_image_url     = string
      lvm_disks          = optional(list(object({ size = number, tier = string })), [])
      pass_through_disks = optional(list(object({ by_id_path = string, tier = string })), [])
    }))
  }))

  validation {
    condition = alltrue([
      for tier in flatten([
        for host in values(var.proxmox_cluster) : [
          for node in values(host.k8s_nodes) : [
            node.lvm_disks[*].tier,
            node.pass_through_disks[*].tier,
          ]
        ]
      ]) : contains(["ssd", "hdd"], tier)
    ])
    error_message = "Every disk tier must be \"ssd\" or \"hdd\"."
  }
  default = {
    # Note if you mean to delete a talos vm and make it differently, delete -> apply -> make new one. Otherwise may only half recreate and be in bad state
    "lab-1" = {
      ip_address = "192.168.1.200"
      k8s_nodes = {
        "talos-cp-01" = {
          ip_address       = "192.168.1.201"
          is_control_plane = true
          boot_disk_size   = 48
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
          boot_disk_size   = 37
          memory           = 4096
          cpu_cores        = 3
          boot_image_url   = "https://factory.talos.dev/image/787b79bb847a07ebb9ae37396d015617266b1cef861107eaec85968ad7b40618/v1.7.4/nocloud-amd64.raw.gz"
        }
        "talos-worker-02" = {
          ip_address       = "192.168.1.204"
          is_control_plane = false
          boot_disk_size   = 40
          memory           = 8192
          cpu_cores        = 5
          boot_image_url   = "https://factory.talos.dev/image/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b/v1.12.6/nocloud-amd64.raw.gz"
          # No lvm carve: shares a disk with control plane and extra I/O would contend with etcd's fsync, our rule ssd or not
        }
      }
    }
    "lab-3" = {
      ip_address = "192.168.1.198"
      k8s_nodes = {
        "talos-worker-03" = {
          ip_address       = "192.168.1.205"
          is_control_plane = false
          boot_disk_size   = 40
          memory           = 14336
          cpu_cores        = 4
          boot_image_url   = "https://factory.talos.dev/image/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b/v1.12.6/nocloud-amd64.raw.gz"
          lvm_disks = [
            { size = 250, tier = "hdd" },
          ]
          pass_through_disks = [
            { by_id_path = "/dev/disk/by-id/ata-WDC_WD30EFRX-68EUZN0_WD-WCC4N0HT7Z2S", tier = "hdd" },
          ]
        }
      }
    }
    "lab-4" = {
      ip_address = "192.168.1.197"
      k8s_nodes = {
        "talos-worker-04" = {
          ip_address       = "192.168.1.206"
          is_control_plane = false
          boot_disk_size   = 40
          memory           = 6144
          cpu_cores        = 3
          boot_image_url   = "https://factory.talos.dev/image/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b/v1.12.6/nocloud-amd64.raw.gz"
          # SSD tier carved from the nvme local-lvm pool; the two HDDs pass through raw as the hdd tier.
          lvm_disks = [
            { size = 250, tier = "ssd" },
          ]
          pass_through_disks = [
            { by_id_path = "/dev/disk/by-id/ata-WDC_WD10SPZX-08Z10_WD-WXK2A80PVJL4", tier = "hdd" },
            { by_id_path = "/dev/disk/by-id/ata-WDC_WD5000AAKX-083CA1_WD-WMAYUX353008", tier = "hdd" },
          ]
        }
      }
    }
    "lab-5" = {
      ip_address = "192.168.1.196"
      k8s_nodes = {
        "talos-cp-03" = {
          ip_address       = "192.168.1.207"
          is_control_plane = true
          boot_disk_size   = 100
          memory           = 4096
          cpu_cores        = 1
          boot_image_url   = "https://factory.talos.dev/image/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b/v1.12.6/nocloud-amd64.raw.gz"
        }
        "talos-worker-05" = {
          ip_address       = "192.168.1.208"
          is_control_plane = false
          boot_disk_size   = 40
          memory           = 10240
          cpu_cores        = 3
          boot_image_url   = "https://factory.talos.dev/image/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b/v1.12.6/nocloud-amd64.raw.gz"
          # No lvm carve: shares a disk with control plane and extra I/O would contend with etcd's fsync
          pass_through_disks = [
            { by_id_path = "/dev/disk/by-id/ata-WDC_WD10EZEX-21M2NA0_WCC3F3NJD56N", tier = "hdd" },
          ]
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
