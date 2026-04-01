#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/.talos-upgrade"
TALOSCONFIG="$CACHE_DIR/talosconfig"
# CP nodes (201, 203, 207) interleaved evenly between workers
NODES=(192.168.1.204 192.168.1.205 192.168.1.201 192.168.1.206 192.168.1.203 192.168.1.208 192.168.1.207)
VERSIONS=(v1.8.4 v1.9.6 v1.10.9 v1.11.6 v1.12.6)

# Preflight: all nodes must be on v1.7
talosctl="$CACHE_DIR/talosctl-v1.7.7"
echo "Preflight: checking all nodes are on v1.7.x..."
for node in "${NODES[@]}"; do
    actual=$("$talosctl" --talosconfig "$TALOSCONFIG" -n "$node" \
        version --short 2>&1 | grep -A2 "Server:" | grep "Tag:" | awk '{print $2}')
    actual_minor="${actual%.*}"
    if [[ "$actual_minor" != "v1.7" ]]; then
        echo "FATAL: $node is on $actual, expected v1.7.x — aborting"
        exit 1
    fi
    echo "  $node: $actual"
done
echo "All nodes on v1.7.x, proceeding."

for v in "${VERSIONS[@]}"; do
    echo "=== Upgrading to $v ==="
    for node in "${NODES[@]}"; do
        echo "  $node: upgrading..."
        "$talosctl" --talosconfig "$TALOSCONFIG" -n "$node" \
            upgrade --image "ghcr.io/siderolabs/installer:$v" -p

        echo "  $node: done"
    done
    echo "=== All nodes on $v ==="
    talosctl="$CACHE_DIR/talosctl-$v"
done

echo "Done."
