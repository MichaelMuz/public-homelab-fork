# Upgrading Talos Linux

## Upgrade path

Must go through each intermediate minor version's latest patch. e.g. v1.7.4 → v1.7.7 → v1.8.4 → v1.9.6 → ...

## Command

```
talosctl upgrade -n <ip> --image <installer-image>:<version>
```

As of Talos v1.8.0+, preserve mode is the default — the `-p` flag was removed entirely.
On v1.7.x and earlier, `-p` was required or the ephemeral partition would be wiped (see incident below).

**Always check `talosctl upgrade --help` for the version you're running** — flags change between versions.

## Installer images and extensions

Docs: https://docs.siderolabs.com/talos/v1.12/platform-specific-installations/virtualized-platforms/proxmox#qemu-guest-agent-support-iso

The bare `ghcr.io/siderolabs/installer` image does **not** include system extensions.
We need qemu-guest-agent (Proxmox VM management), iscsi-tools (Longhorn), and util-linux-tools.

Use Image Factory to get an installer that bundles them:
https://factory.talos.dev/

Our schematic:
```yaml
customization:
    systemExtensions:
        officialExtensions:
            - siderolabs/qemu-guest-agent
            - siderolabs/util-linux-tools
            - siderolabs/iscsi-tools
```

The schematic ID changes between Talos versions — regenerate on the factory site for each new version.
You can verify what extensions a schematic includes:
```
curl https://factory.talos.dev/schematics/<id>
```

The upgrade command with a factory image:
```
talosctl upgrade -n <ip> --image factory.talos.dev/nocloud-installer/<schematic-id>:<version> -p
```

You don't need the factory image for every intermediate hop — you can upgrade through minor versions
with the bare installer and do a final upgrade-in-place to the factory image on the target version
to restore extensions.

## talosctl version

Use a talosctl binary matching the node's **current** running version. Download from:
`https://github.com/siderolabs/talos/releases/download/<version>/talosctl-linux-amd64`

## Control plane nodes

Talos refuses to upgrade a CP node if etcd quorum would be lost. If you get a mutex or etcd health error, another CP node is mid-upgrade. Wait and retry.

## Troubleshooting stuck nodes

After upgrading some nodes, remaining nodes may show etcd errors or appear `NotReady` in `kubectl get nodes`.
Rebooting the stuck node usually fixes it:
```
talosctl -n <ip> -e <ip> reboot
```
This also waits for the node to come back and errors if the reboot fails. Once healthy, retry the upgrade.

# Scripting
Note that as long as you wait for it you can just do each node in a row (default is to --wait, it not sending a stderr is enough to make sure it is fine)
This means you can have a script that does one node at a time and as long as the request waits and doesn't error you can just keep moving on
Scripts are in `scripts/talos-upgrade/`. Past upgrade scripts are kept in `history-*` subdirs as reference.

## Before upgrading

Treat `Available upstream` in `VERSIONS.md` as an informational target. Update `Current/live version`
only after the attended Talos or Kubernetes upgrade has completed.

Back up etcd:
```
talosctl etcd snapshot db.snapshot --nodes <CP_IP>
```

## After all nodes upgraded

1. `tofu apply` the talos provider (provider version must match OS version's SDK)
2. Kubernetes upgrade is separate from the OS upgrade — see `talosctl upgrade-k8s`

## References

- Proxmox guide: https://docs.siderolabs.com/talos/v1.12/platform-specific-installations/virtualized-platforms/proxmox
- Terraform upgrade guide: https://oneuptime.com/blog/post/2026-03-03-upgrade-talos-linux-clusters-with-terraform/view

# Data loss incident — 2026-03-25

## Cause

Talos OS upgrade on talos-worker-02 (192.168.1.204) ran without `--preserve` flag, wiping the ephemeral partition. All Longhorn replicas on that node were destroyed. Volumes with no replicas on other nodes are unrecoverable.

