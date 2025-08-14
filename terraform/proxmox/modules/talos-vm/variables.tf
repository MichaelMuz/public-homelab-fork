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
    ip_address = string
    disk_size  = number
    memory     = number
    cpu_cores  = number
  }))
  description = "Map of each vm name to its config. Disk and memory are in gb and cpu cores are logical threads"
}
