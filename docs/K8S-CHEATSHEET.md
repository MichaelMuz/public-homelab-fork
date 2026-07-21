# K8s Cheatsheet

## Helm: show a chart's values.yaml

```bash
helm show values longhorn --repo https://charts.longhorn.io --version 1.11.1
```

No `helm repo add` needed.

## kubectl: explore CRD fields

```bash
kubectl explain volume.spec
```

Drill into nested fields by appending them: `volume.spec.numberOfReplicas`. Add `--api-version=longhorn.io/v1beta2` if the resource name is ambiguous across API groups.

## kubectl: list all resource types

```bash
kubectl api-resources
```

Filter to a group: `kubectl api-resources --api-group=longhorn.io`.

## cnpg: see instance roles + node placement

```bash
kubectl cnpg status <cluster> -n <ns>
```

"Instances status" table shows `Primary` / `Standby (sync)` / `Standby (async)` and the node each runs on.

## Longhorn: see a volume's node + locality

```bash
kubectl get pvc <pvc> -n <ns> -o jsonpath='{.spec.volumeName}'   # PVC -> PV name
kubectl get volumes.longhorn.io -n longhorn-system <pv> \
  -o custom-columns='NODE:.spec.nodeID,LOCALITY:.spec.dataLocality,REPL:.spec.numberOfReplicas'
```

`LOCALITY: strict-local` = replica pinned to the pod's node; `disabled` = old non-local volume.
