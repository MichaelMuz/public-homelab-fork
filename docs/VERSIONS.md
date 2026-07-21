# Homelab versions

Current/live versions verified 2026-07-01:

- Proxmox
- Terraform providers
- Talos
- Kubernetes
- Helm charts

## Not declared in IaC

| Component                        | Current/live version | Available upstream |
|----------------------------------|----------------------|--------------------|
| Proxmox VE (lab-1 through lab-5) | 9.2.3                | manual             |
| Proxmox kernel                   | 7.0.12-1-pve         | manual             |
<!-- renovate: datasource=github-releases depName=siderolabs/talos versioning=semver -->
| Talos Linux                      | v1.12.6              | v1.12.9            |
<!-- renovate: datasource=github-releases depName=kubernetes/kubernetes versioning=semver -->
| Kubernetes                       | v1.35.0              | v1.35.6            |
<!-- renovate: datasource=github-releases depName=siderolabs/talos versioning=semver -->
| talosctl                         | v1.12.6              | v1.12.9            |
<!-- renovate: datasource=github-releases depName=kubernetes/kubernetes versioning=semver -->
| kubectl                          | v1.35.0              | v1.35.6            |

## Notes

- Promtail is EOL as of 2026-03-02, migrate to Alloy
- Loki chart is migrating to the community repo
- CRDs are updated by ArgoCD on sync. Helm's limitation of not upgrading CRDs doesn't affect us
- Renovate updates only `Available upstream`; record `Current/live version` after an attended upgrade
