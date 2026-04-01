#!/usr/bin/env python3
"""Check which PVCs have a Longhorn replica on worker-05."""

import json
import subprocess

def run(cmd):
    return json.loads(subprocess.check_output(cmd, shell=True))

pvcs = run("kubectl get pvc -A -o json")
replicas = run("kubectl get replicas.longhorn.io -n longhorn-system -o json")

# Map volume name -> PVC info
vol_to_pvc = {}
for pvc in pvcs["items"]:
    vol = pvc["spec"].get("volumeName")
    if vol:
        vol_to_pvc[vol] = {
            "namespace": pvc["metadata"]["namespace"],
            "name": pvc["metadata"]["name"],
        }

# Group replicas by volume
vol_replicas = {}
for r in replicas["items"]:
    vol = r["spec"]["volumeName"]
    node = r["spec"]["nodeID"]
    state = r["status"].get("currentState", "unknown")
    vol_replicas.setdefault(vol, []).append({"node": node, "state": state})

# Report
print(f"{'NAMESPACE':<14} {'PVC':<45} {'ON W05?':<10} {'W05 STATE':<12} {'TOTAL REPLICAS'}")
print("-" * 110)

for vol, pvc_info in sorted(vol_to_pvc.items(), key=lambda x: x[1]["name"]):
    reps = vol_replicas.get(vol, [])
    w05 = [r for r in reps if r["node"] == "talos-worker-05"]
    on_w05 = "YES" if w05 else "NO"
    w05_state = w05[0]["state"] if w05 else "-"
    rep_summary = ", ".join(f"{r['node'].replace('talos-', '')}({r['state']})" for r in reps)
    print(f"{pvc_info['namespace']:<14} {pvc_info['name']:<45} {on_w05:<10} {w05_state:<12} {rep_summary}")
