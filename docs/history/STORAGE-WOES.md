# Storage woes (solved 2026-07-01)

Historical record of the lab's storage problem area and how each issue was crossed off. This
was the #1 priority for weeks; it is now closed. Live disk policy is in `../PROXMOX-STORAGE.md`,
Longhorn in `../DISTRIBUTED-STORAGE.md`. This file is an artifact, kept as a record of what we
set out to do and how we did it.

## Final storage nodes

| Node      | Host         | Longhorn disks                       | Tags     | Reserve | Notes                                                                 |
|-----------|--------------|--------------------------------------|----------|---------|-----------------------------------------------------------------------|
| worker-02 | lab-2 (.199) | none                                 | -        | -       | diskless by design; shares lab-2 with cp-02, kept out of Longhorn     |
| worker-03 | lab-3 (.198) | 2 (250G lvm + 2.7T passthrough)      | hdd      | 0       | remade/unfused 2026-06-29                                             |
| worker-04 | lab-4 (.197) | 3 (250G ssd lvm + 2 hdd passthrough) | ssd, hdd | 0       | reference split model                                                 |
| worker-05 | lab-5 (.196) | 1 (1TB passthrough)                  | hdd      | 0       | dedicated spindle; OS moved to a 500G disk 2026-07-01 to free the 1TB |

Every disk sits at reserve 0; ~6 TB fully schedulable.

## How each woe was crossed off

1. **No tiered StorageClasses.** Built 2026-06-30: `hdd` is the default SC, `ssd` opt-in
   (`longhorn-ssd`), the PG SC pins `hdd`. The hdd tier reached three nodes (03/04/05) on
   2026-07-01 when worker-05 became a real hdd node, so default volumes now heal to a full
   3 replicas instead of being born degraded 2/3. The ssd tier exists but stays single-node
   (worker-04 only), so it is opt-in and can't do multi-replica yet, a known, accepted limit.

2. **PG HA.** Done 2026-06-30. Both PG clusters (expense-splitter, immich) run strict-local
   single-replica volumes, one instance per node across worker-03/04/05 via required pod
   anti-affinity. `nodeDrainPolicy: allow-if-replica-is-stopped` lets node drains proceed.

3. **Existing reserves oversized.** Closed 2026-07-01. The global
   `storageReservedPercentageForDefaultDisk` was set to 0, so new disks are born at 0; the
   pre-existing 30% disks on worker-03/04 were kicked to 0 in the UI, reclaiming ~1.5 TiB.
   Existing-disk reserve is not declaratively manageable (the global and the per-disk
   annotation both apply only at disk creation), so this was a one-time manual cleanup.

4. **Replica count not declarative.** By design, not a woe. SCs omit replica count (Longhorn's
   global default applies at creation), then it is tuned per-volume in the UI. Longhorn volume
   CRs are dynamically named (`pvc-<uuid>`), so there is no stable git object to set it on.

## The last remakes: two dual-node boxes (2026-07-01)

The final blockers were lab-5 and lab-2, each running a control plane and a worker on one host,
untouched since the move to the split-disk model.

- **lab-5 / worker-05.** worker-05 was a single fused HDD sharing the spindle with cp-03's
  etcd. We reinstalled Proxmox onto a spare 500 GB disk so the whole 1 TB could pass through
  to worker-05 as a *dedicated* hdd spindle, keeping etcd's fsync off Longhorn's I/O path.
  cp-03 was rebuilt and rejoined etcd as a fresh member.
- **lab-2 / worker-02.** Retired the "reserve > total" hack that had sidelined it. Remade with
  no disk entries; with `createDefaultDiskLabeledNodes: true`, an unlabeled node gets zero
  Longhorn storage declaratively, no hack needed.

## Lessons banked

- **Don't carve a Longhorn lvm disk out of a disk shared with a control plane.** Replica write
  I/O contends with etcd's fsync on the same spindle and can destabilize the control plane.
  Pass through a dedicated disk instead (worker-05 got a dedicated 1 TB; worker-02 got nothing).
- **Remaking a Talos VM with different specs:** remove it from the terraform node map, apply
  (destroys the VM *and* its `talos_machine_configuration_apply`), re-add, apply. A plain VM
  delete/replace only half-recreates: the VM returns but its config-apply is skipped, leaving
  it stuck in maintenance mode.
- **`talos_cluster_health` gates every apply on "all nodes schedulable".** That deadlocks an
  apply while a node is intentionally cordoned or mid-remake. Gate manually via `talosctl
  health` during disruptive changes.
