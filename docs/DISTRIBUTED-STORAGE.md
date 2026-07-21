# Distributed Storage

## RWO vs RWX and Rollouts

We should consider making all volumes RWX where we plan to do rollouts. Rollouts involving pods with RWO PVCs rely on luck to schedule the new pod on the same node as the old pod. The Kubernetes scheduler does not seem to account for this, at the very least in the presence of node failures. When a node comes back up, the scheduler may place the new pod there instead of on the node holding the volume, causing a Multi-Attach deadlock.

The `monitoring` namespace seems to rollout once a day or so (scheduled ArgoCD syncs maybe?), making it the most affected. We don't really rollout much anywhere else.

RWO is per-node, not per-pod. Two pods on the same node can share an RWO volume. The deadlock only happens cross-node. This means the problem is intermittent and hard to notice until a node failure changes scheduling decisions.

Note: Longhorn's force-delete-workload setting does **not** help with this. That setting handles the case where a pod on a dead node is stuck Terminating and holding a volume. The rollout deadlock happens when both nodes are alive and the old pod is healthy — Longhorn sees nothing wrong.

## Storage tiers and StorageClasses

Two tiers, chosen by disk tag: `hdd` is the default (it's the abundant disk); `ssd` is opt-in via `longhorn-ssd`.

- We don't IAC replica counts, they are all default and hand-tuned in the UI except for PG storage since it does its own replication and needs a replica count of 1
- `diskSelector` steers new provisioning only. Some active PVCs predate the selector and run on an older SC — fine, they already sit on hdd. Don't be surprised about an old PVC sitting somewhere, its originating storage class may have had fewer constraints. (all PVC on hdd at time of adding the default storage class's hdd selector)

### Changing a StorageClass parameter means delete + recreate

SC `parameters` and `volumeBindingMode` are immutable, so Argo's sync fails: `StorageClass "longhorn-pg-single-replica" is invalid: parameters: Forbidden: updates to parameters are forbidden`. Delete it and Argo recreates it next sync:

```bash
kubectl delete storageclass longhorn-pg-single-replica
```

Safe: bound volumes aren't affected, new volumes can use this new storage class

## CloudNativePG HA on Longhorn

CloudNativePG does HA at the PG layer via streaming replication between instances. For this to be real HA on Longhorn, each instance's volume must live on a different node. Longhorn's default placement doesn't know instances are related, so without explicit constraints it can place every volume on the same node — fake HA. 

### Desired state - Achieved 06/30/26

- Each PG Cluster instance runs on a distinct node.
- Each instance's Longhorn volume has one replica, co-located with its pod.
- Longhorn does not do storage-level HA for PG volumes; PG does.
- Node drains succeed without manual intervention.

### StorageClass (`longhorn-pg-single-replica`)

- `numberOfReplicas: "1"` — PG handles replication. Extra replicas cause write amplification and risk co-location with another instance's data.
- `dataLocality: "strict-local"` — the one replica stays on the pod's node. Disables Longhorn-level HA, which is what we want here.
- `volumeBindingMode: WaitForFirstConsumer` — scheduler picks the node first, then Longhorn provisions the volume there. Without this, Longhorn may pick a node at PVC creation and pin the pod.

### Cluster affinity (per cnpg Cluster)

- `enablePodAntiAffinity: true`
- `topologyKey: kubernetes.io/hostname`
- `podAntiAffinityType: required` — hard requirement. When node capacity is insufficient, Pending pods are the correct state; soft anti-affinity silently creates fake HA.

### Longhorn drain policy (global)

Default (`block-if-contains-last-replica`) refuses drain when a node holds a volume's last replica. With strict-local + 1 replica, every PG replica is the last — drains would always block on PG nodes. `block-for-eviction*` options don't help either: they try to evict replicas elsewhere, which strict-local forbids, so drains block indefinitely. Set to `allow-if-replica-is-stopped` — the eviction flow (pod evicts → volume detaches → replica stops) naturally satisfies this, so drain proceeds without manual intervention. Fleet-wide setting; acceptable because non-PG volumes default to multi-replica in this cluster.

### How we migrated to this state

SC changes only apply to newly provisioned PVCs. Existing PG volumes keep their current (non-local, disabled-locality) settings until recreated.

What we did:
1. Applied the SC + Cluster changes declaratively. The SC had to be deleted and recreated, not patched, since `volumeBindingMode` and `parameters` are immutable.
2. Destroyed each standby with `kubectl cnpg destroy <cluster> <n>`. cnpg rebuilt it under a new ordinal, and the fresh PVC came up strict-local and node-local.
3. Waited for the rebuilt instance to rejoin and stream-catch-up before the next one.
4. For the primary, switched over first with `kubectl cnpg promote <cluster> <standby>`, then destroyed the demoted old primary.

Each rebuild cost one `pg_basebackup` over the network. Acceptable for our DB sizes.

## Consequences of letting the scheduler pick PG nodes

`WaitForFirstConsumer` hands node choice to the kube-scheduler, which sees pod constraints and node labels only — nothing about Longhorn disks. So to pin PG to a tier, the Cluster `nodeSelector` and the SC `diskSelector` must agree, both keyed on a node **label** (`machine.nodeLabels` in Talos, e.g. `storage-tier: hdd`)

- They must agree — `nodeSelector: {storage-tier: hdd}` on the Cluster, `diskSelector: ["hdd"]` on the SC. Disagree and the pod lands where Longhorn won't provision a local replica, and the volume hangs.
- Compute nodes excluded for free — no `storage-tier` label means a tiered selector skips them. Absence of the label is the exclusion; one mechanism covers tier, storage-node, and not-compute at once.
- Full nodes are an open problem — the scheduler is blind to Longhorn free space, so it can pick a labeled node with no room and the replica fails to provision. Maybe - CSIStorageCapacity tracking?
