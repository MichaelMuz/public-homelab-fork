This is the next thing I should work on in my homelab

# Backup strategy (3-2-1)

Three copies, two media types, one offsite.

- **3 copies:** Longhorn replicates volumes across 3 nodes (2 for media).
- **2 media types:** Local disk (Longhorn) + cloud object storage (Cloudflare R2 or similar).
- **1 offsite:** The cloud backup.

Longhorn covers rule 1 and half of rule 2. An S3 backup target covers the other half of rule 2 and rule 3.

## What to back up

Go through each PVC in the cluster and decide: would I care if this disappeared? Configure Longhorn recurring backups on the volumes that matter. Skip anything re-downloadable or ephemeral.

## How

Longhorn has built-in recurring backup to S3-compatible storage

1. Create an S3 bucket + API credentials (pick the cheapest provider — R2 has a free tier and you already use Cloudflare)
2. Configure the backup target in Longhorn settings (secret + S3 URL)
3. Set recurring backup schedules per volume (or as a StorageClass-level default)
4. Test a restore

## Next steps

- [ ] Pick S3 provider + create bucket
- [ ] Deploy Longhorn backup target config via Helm values
- [ ] Tag volumes for backup schedules
- [ ] Test a full restore cycle

## Terraform state

Local `terraform.tfstate` today, no backend. We want a remote backend (S3-compatible, with locking)
