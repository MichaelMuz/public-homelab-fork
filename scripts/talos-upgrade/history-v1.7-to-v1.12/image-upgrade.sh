#!/bin/bash
set -euo pipefail

# Re-upgrade all nodes to the same version but with a factory image that includes extensions.
# Use this after a multihop upgrade that used bare installer images.

IMAGE="factory.talos.dev/nocloud-installer/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b:v1.12.6"

# CP nodes (201, 203, 207) interleaved evenly between workers
NODES=(192.168.1.204 192.168.1.205 192.168.1.201 192.168.1.206 192.168.1.203 192.168.1.208 192.168.1.207)

echo "Upgrading all nodes to image: $IMAGE"

for node in "${NODES[@]}"; do
    echo "  $node: upgrading..."
    talosctl -n "$node" -e "$node" \
        upgrade --image "$IMAGE" -p

    echo "  $node: done"
done

echo "Done."
