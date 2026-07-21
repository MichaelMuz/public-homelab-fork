# Proxmox storage

## Host drives

| Host | Drives | VG `pve` members |
|---|---|---|
| lab-1 (.200) | 113 GB Apple SSD (`sda`) | `sda3` |
| lab-2 (.199) | 477 GB NVMe (`nvme0n1`) | `nvme0n1p3` |
| lab-3 (.198) | 465 GB HGST HDD (`sda`) + 2.7 TB WD Red HDD (`sdb`) | `sda3`, `sdb` (fused, see below) |
| lab-4 (.197) | 477 GB NVMe (`nvme0n1`) + 931 GB WD HDD (`sda`) + 465 GB WD HDD (`sdb`) | `nvme0n1p3` only (`sda`/`sdb` raw passthrough) |
| lab-5 (.196) | 931 GB WD HDD (`sda`) | `sda3` |

lab-3 still has its `sdb` fused into VG `pve` (done 2026-03-29/30 after a thin pool exhaustion incident; thin pool ~342 GB -> ~794 GB). worker-03 was remade with `disk_size = 750` then since the exhaustion left Talos reporting a corrupt filesystem via medium errors. lab-4 was the same until its 2026-06-29 rebuild to the split model (boot + carved SSD slice on the nvme, the two HDDs passed through raw).

## Thin provisioning gotchas

VM disks are thin-provisioned on the `data` thin pool. Overcommit is allowed — a VM can claim more space than the pool physically has. If actual usage hits 100%, **all VM I/O stops** (Proxmox shows `qmpstatus: io-error`). The VM won't recover on its own; the pool must be extended or data freed, then the VM restarted.

`qm resize` only grows disks. To shrink a VM disk, destroy and recreate the VM. For Talos workers this is non-destructive (stateless OS, Longhorn re-replicates).

## Node disk allocation policy

- Splitting **one** physical disk into boot + Longhorn is fine. Shared fate, but boot is disposable so it does not matter.
- Merging **several** physical disks into **one** Longhorn disk is a lie that doubles failure risk. This is exactly the VG `pve` fusion on lab-3 and lab-4 above, done under duress during the thin pool incidents, and it should be undone.

Longhorn redundancy comes from **other nodes**, not from multiple disks on one node. Longhorn will not place two replicas of the same volume on one node, so extra disks per node buy capacity and failure isolation, never replica safety. Split down freely, never merge up.

Precedence when provisioning a node:
1. Install Proxmox on the smallest disk (SSD if present). This creates `local-lvm` there.
2. Boot Talos disk: small fixed size carved from that `local-lvm`, the `virtio0` disk in Terraform and the only one with a `file_id`. Proxmox and Talos boot coexist as partitions on one physical disk. This stays datastore-backed so the common single-disk node is still pure copy-paste.
3. Leftover space on that disk: a second VM disk from `local-lvm` for Longhorn. Shares fate with boot, which is acceptable.
4. Every other whole disk: raw pass-through straight to the VM. No thin pool, so no overcommit footgun, no magic-number sizing (pass-through takes no `size`, Longhorn gets the whole real device), and still fully declarative.

Pass-through in bpg is experimental but fine for our stateless workers (a bad disk means a rebuild, Longhorn re-replicates). It uses an empty `datastore_id` and no `size`:
```hcl
disk {
  datastore_id      = ""
  path_in_datastore = "/dev/disk/by-id/ata-..."
  file_format       = "raw"
  interface         = "virtio1"
}
```
Always use a stable `/dev/disk/by-id/` path (model+serial), never `/dev/sdX` which can reorder across boots and would point Longhorn at the wrong disk. The id travels with the physical disk, so it survives moving the drive to another host or SATA port. Find it on the host with `lsblk -o NAME,SIZE,MODEL,SERIAL,WWN` or `ls -l /dev/disk/by-id/`. Never attach one host disk to two VMs (data corruption).

All nodes are now on the split model: lab-3 (2026-06-29, unfused), lab-4 (2026-06-29, small boot + carved SSD slice + 2 raw passthrough HDDs), and lab-5 (2026-07-01, boot moved to a 500 GB disk so the whole 1 TB passes through to worker-05). worker-02 runs diskless (no Longhorn storage). The full migration story is recorded in `history/STORAGE-WOES.md`.
