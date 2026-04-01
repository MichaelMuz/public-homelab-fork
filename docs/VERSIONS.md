# Homelab versions

Up to date as of 2026-03-27:

- Proxmox
- Terraform providers
- Talos
- Kubernetes
- Helm charts

## Not declared in IaC

| Component                        | Version |
|----------------------------------|---------|
| Proxmox VE (lab-1 through lab-5) | 9.1.6   |
| Talos Linux                      | v1.12.6 |
| Kubernetes                       | v1.35.0 |
| talosctl                         | v1.12.6 |
| kubectl                          | v1.35.0 |

## Notes

- Promtail is EOL as of 2026-03-02, migrate to Alloy
- Loki chart is migrating to the community repo
- CRDs are updated by ArgoCD on sync. Helm's limitation of not upgrading CRDs doesn't affect us
