variable "default_gateway" {
  description = "Router's IP"
  type        = string
  default     = "192.168.1.1"
}

variable "proxmox_node" {
  type = object({
    name = string
    ip   = string
  })
}

variable "talos_nodes" {
  type = map(object({
    ip_address         = string
    boot_disk_size     = number
    memory             = number
    cpu_cores          = number
    boot_image_url     = string
    lvm_disks          = optional(list(object({ size = number, tier = string })), [])
    pass_through_disks = optional(list(object({ by_id_path = string, tier = string })), [])
  }))
  description = "Map of each vm name to its config. Disk and memory are in gb and cpu cores are logical threads. Boot image only represents what was installed, upgrades may have been performed later."
}
