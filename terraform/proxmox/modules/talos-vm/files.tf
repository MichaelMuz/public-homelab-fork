locals {
  vm_to_boot_info = { for name, node in var.talos_nodes :
    name => {
      version = regex("v[0-9]+\\.[0-9]+\\.[0-9]+", node.boot_image_url)
      url     = node.boot_image_url
    }
  }
  version_to_image_url = { for boot_info in distinct(values(local.vm_to_boot_info)) : boot_info.version => boot_info.url }
}

resource "proxmox_virtual_environment_download_file" "talos_nocloud_image" {
  for_each = local.version_to_image_url

  content_type = "iso"
  datastore_id = "local"
  node_name    = var.proxmox_node.name

  file_name               = "talos-${each.key}-nocloud-amd64.img"
  url                     = each.value
  decompression_algorithm = "gz"
  overwrite               = false
}
