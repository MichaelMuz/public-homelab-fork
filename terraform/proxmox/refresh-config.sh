#!/usr/bin/env bash
# Pull the current kube + talos configs from Terraform state and install them,
# clobbering whatever is in place. Keeps a single .bak of each from just before.
set -euo pipefail
cd "$(dirname "$0")"

kube="$HOME/.kube/config"
talos="$HOME/.talos/config"

mkdir -p "$(dirname "$kube")" "$(dirname "$talos")"

if [ -f "$kube" ]; then cp "$kube" "$kube.bak"; fi
if [ -f "$talos" ]; then cp "$talos" "$talos.bak"; fi

tofu output -raw kubeconfig >"$kube"
tofu output -raw talosconfig >"$talos"

echo "refreshed $kube and $talos (prev saved as *.bak)"
echo
echo "copy each:"
echo "  wl-copy < $kube"
echo "  wl-copy < $talos"
