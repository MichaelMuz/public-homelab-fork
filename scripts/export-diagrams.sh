#!/bin/bash
set -euo pipefail

DRAWIO="docs/diagrams/network_diagram.drawio"
OUT="docs/diagrams/images"

drawio --export --format svg --page-index 1 --output "$OUT/network_topology.svg" "$DRAWIO"
drawio --export --format svg --page-index 2 --output "$OUT/cluster_architecture.svg" "$DRAWIO"
drawio --export --format svg --page-index 3 --output "$OUT/traffic_flows.svg" "$DRAWIO"
drawio --export --format svg --page-index 4 --output "$OUT/blast_radius.svg" "$DRAWIO"
