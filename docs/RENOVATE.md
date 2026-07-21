# Renovate dependency automation

Renovate opens dependency MRs for the homelab repo as drafts. It does not merge them.

## Review status

Draft is the review gate, not just a title convention:

- Renovate creates every MR as Draft and assigns it to Hermes without requesting Michael's review.
- A deterministic Hermes poller detects each new exact head and queues an isolated assessment.
- A clean assessment records an exact-head marker, removes Draft status, and requests Michael's review.
- A blocked assessment records its findings and leaves the MR as Draft.
- If Renovate changes a previously reviewed head, the poller returns the MR to Draft before queuing the new assessment. For now this just runs in a hermes cron script.

Only non-Draft Renovate MRs are ready for Michael's final review.

## What Renovate watches

- Helm chart dependencies in `kubernetes/apps/*/Chart.yaml`.
- Conventional image fields in Helm values.
- OpenTofu/Terraform provider constraints under `terraform/**`.
- Literal image pins in Kubernetes app YAML and Helm templates, through a regex custom manager.
- Talos and Kubernetes availability fields in `docs/VERSIONS.md`, through inline Renovate comments.

## Custom managers

The regex managers cover repo-specific version strings that Renovate's built-in managers do not see.

`docs/VERSIONS.md` rows use comments like:

```html
<!-- renovate: datasource=github-releases depName=siderolabs/talos versioning=semver -->
```

Renovate reads the comment and updates only the `Available upstream` field. The `Current/live version`
field records attended upgrades and is never a Renovate target. Availability MRs can merge before an
upgrade because they do not claim that the cluster or CLI tools changed.

The two Actions Runner Controller chart dependencies are grouped into one MR when they share an
upstream release.

The image regex manager scans Kubernetes app YAML for literal `image: repo:tag` references that are not represented as normal Helm values.

## Runtime credentials

- `RENOVATE_TOKEN`: GitLab project access token, Developer role, `api` scope, expires 2027-07-08.
- `RENOVATE_GITHUB_COM_TOKEN`: fine-grained GitHub token, public repository read-only, no expiration. Used for GitHub release and changelog lookups.

Hermes's Renovate review workflow is documented in [HERMES-AGENT.md](HERMES-AGENT.md#renovate-reviews).

## Limits

- Proxmox VE and Proxmox kernel rows stay manual for now, Renovate does not have a clean datasource for those repo/package versions in this setup.
- Argo CD Image Updater still owns live image digest pinning for apps configured through it. Renovate is the broader repo dependency bot, not a replacement for every image automation path.
