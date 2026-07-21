resource "talos_machine_secrets" "machine_secrets" {}

data "talos_client_configuration" "talosconfig" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  endpoints            = local.control_plane_node_ips
}

# need one meeting point for cluster bootstrap, control plane 1 will coordinate boostrap
data "talos_machine_configuration" "machineconfig_cp" {
  cluster_name     = var.cluster_name
  cluster_endpoint = local.cluster_bootstrap_endpoint
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.machine_secrets.machine_secrets
  config_patches = [
    yamlencode({
      machine = {
        install = {
          extraKernelArgs = [
            # Disable predictable interface naming so all VMs use eth0.
            # MetalLB L2Advertisement is configured to announce only on eth0;
            # without this, new nodes could get names like enx... and be skipped.
            "net.ifnames=0",
            "biosdevname=0",
          ]
        }
      }
      # Disabled — Cilium replaces both default CNI and kube-proxy.
      cluster = {
        network = {
          cni = {
            name = "none"
          }
        }
        proxy = {
          disabled = true
        }
      }
    })
  ]
}

resource "talos_machine_configuration_apply" "cp_config_apply" {
  for_each = local.control_plane_nodes
  # cannot be more granular and depend on specific vm in module
  # MUST specify dependencies statically, can't even use a local variable
  depends_on                  = [module.vms]
  client_configuration        = talos_machine_secrets.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.machineconfig_cp.machine_configuration
  node                        = each.value.ip_address
}

data "talos_machine_configuration" "machineconfig_worker" {
  cluster_name     = var.cluster_name
  cluster_endpoint = local.cluster_bootstrap_endpoint
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.machine_secrets.machine_secrets
  config_patches = [
    yamlencode({
      machine = {
        install = {
          extraKernelArgs = [
            # Disable predictable interface naming so all VMs use eth0.
            # MetalLB L2Advertisement is configured to announce only on eth0;
            # without this, new nodes could get names like enx... and be skipped.
            "net.ifnames=0",
            "biosdevname=0",
          ]
        }
      }
      # Disabled — Cilium replaces both default CNI and kube-proxy.
      cluster = {
        network = {
          cni = {
            name = "none"
          }
        }
        proxy = {
          disabled = true
        }
      }
    })
  ]
}

resource "talos_machine_configuration_apply" "worker_config_apply" {
  for_each = local.worker_nodes
  # cannot be more granular and depend on specific vm in module
  # MUST specify dependencies statically, can't even use a local variable
  depends_on                  = [module.vms]
  client_configuration        = talos_machine_secrets.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.machineconfig_worker.machine_configuration
  node                        = each.value.ip_address

  config_patches = length(local.worker_disks[each.key]) == 0 ? null : [
    yamlencode({
      machine = {
        # Mount this node's extra disks and register them with Longhorn.
        disks = [
          for disk in local.worker_disks[each.key] : {
            device     = disk.device
            partitions = [{ mountpoint = disk.mountpoint }]
          }
        ]
        nodeLabels = {
          # Setting tells longhorn that the below `default-disks-config` contains disks to adopt
          "node.longhorn.io/create-default-disk" = "config"
        }
        nodeAnnotations = {
          "node.longhorn.io/default-disks-config" = jsonencode([
            for disk in local.worker_disks[each.key] : {
              path            = disk.mountpoint
              allowScheduling = true
              storageReserved = 0 # longhorn default settings seem to override this. Could be the more conservative number wins
              tags            = disk.tags
            }
          ])
        }
      }
    })
  ]
}

resource "talos_machine_bootstrap" "bootstrap" {
  depends_on           = [talos_machine_configuration_apply.cp_config_apply]
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  node                 = local.bootstrap_node.ip_address
}

data "talos_cluster_health" "health" {
  # depend on all of this for explicitness
  depends_on           = [talos_machine_configuration_apply.cp_config_apply, talos_machine_configuration_apply.worker_config_apply, talos_machine_bootstrap.bootstrap]
  client_configuration = data.talos_client_configuration.talosconfig.client_configuration
  control_plane_nodes  = local.control_plane_node_ips
  worker_nodes         = local.worker_node_ips
  endpoints            = data.talos_client_configuration.talosconfig.endpoints
}

resource "talos_cluster_kubeconfig" "kubeconfig" {
  depends_on           = [talos_machine_bootstrap.bootstrap, data.talos_cluster_health.health]
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  node                 = local.bootstrap_node.ip_address
}

