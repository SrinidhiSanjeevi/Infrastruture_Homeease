# SonarQube — persistence, backup, and restore

Infrastructure: `terraform/azure/modules/sonarqube-vm/`. This document is the
"what's persistent, where, how backed up, how restored" record that
infrastructure-as-code alone doesn't make obvious.

## What is persistent, and where

| Data | Lives on | Survives... |
|---|---|---|
| SonarQube's own data (search index, plugins/extensions, logs) | `/data/sonarqube/{data,extensions,logs}` on the **managed data disk** (`azurerm_managed_disk.data`) | Container recreation, `docker compose down`, VM reboot. **Not** VM deletion — the disk is a separate Azure resource but is not currently detached-and-preserved on `terraform destroy`. |
| SonarQube projects, analysis history, Quality Gate config, users | **Postgres**, at `/data/postgres` on the same managed data disk | Same as above |
| Postgres credentials | `/opt/sonarqube/.env` on the VM's **OS disk**, generated once at first boot by cloud-init, never passed through Terraform | VM reboot. **Not** OS disk replacement — if you ever rebuild the OS disk, Postgres itself is unaffected (its data is on the data disk) but you'd need the container to be re-pointed at the same password, which is why backups exist. |
| Nightly Postgres dumps | Azure Blob Storage, `stsonarbkp<env><hash>` / `sonarqube-backups` container, uploaded via the VM's Managed Identity | VM deletion, disk deletion, region-level LRS failure is the only thing that takes this out too — see "Limitations" below |

**What is NOT persistent, deliberately:** the SonarQube and Postgres **containers**
themselves. `docker compose pull && docker compose up -d` recreating them from
scratch is expected and safe — all state they'd lose lives on the mounted
volumes above, not in the container's writable layer.

## Backup

- **What:** `pg_dump` of the `sonarqube` database, gzip-compressed
- **Where:** `https://<backup_storage_account>.blob.core.windows.net/sonarqube-backups/<UTC-timestamp>.sql.gz`
- **Frequency:** nightly at 02:00 UTC (`systemd` timer `sonarqube-backup.timer`, `RandomizedDelaySec=600` so it doesn't fire at the exact same second every night)
- **Retention:** 30 days by default (`var.sonarqube_backup_retention_days`), enforced by an `azurerm_storage_management_policy` lifecycle rule — Azure deletes old blobs itself, nothing on the VM has to remember to clean up
- **Auth:** the VM's system-assigned Managed Identity, granted `Storage Blob Data Contributor` on the backup storage account only. No key, no connection string, no SAS token exists anywhere.
- **What is NOT backed up separately:** SonarQube's `/data/sonarqube/extensions` (installed plugins) and its search index. Plugins are reproducible from the SonarQube Marketplace by hand if ever lost; the search index is rebuilt by SonarQube itself from Postgres data on next startup if it's ever missing or corrupt — Postgres is the actual source of truth, which is exactly what's backed up.

## Restore procedure

1. Provision (or reuse) a VM via this same Terraform module — `terraform apply` recreates everything except the Postgres data itself.
2. Download the backup you want:
   ```bash
   AZCOPY_AUTO_LOGIN_TYPE=MSI azcopy copy \
     "https://<backup_storage_account>.blob.core.windows.net/sonarqube-backups/<timestamp>.sql.gz" \
     /tmp/restore.sql.gz
   ```
3. Stop SonarQube (keep Postgres up), then restore:
   ```bash
   cd /opt/sonarqube
   docker compose stop sonarqube
   gunzip -c /tmp/restore.sql.gz | docker compose exec -T postgres psql -U sonarqube -d sonarqube
   docker compose start sonarqube
   ```
4. Confirm: log in, check that projects/analysis history/Quality Gates are back.

## What happens if...

- **The container is deleted/recreated:** nothing lost — recreate with `docker compose up -d`, it reattaches to the same data disk paths.
- **The VM is deleted but the data disk survives:** attach the disk to a new VM (or a new `terraform apply` of this module, then manually re-attach the existing disk instead of letting it create a new empty one), remount at `/data`, `docker compose up -d`. No data loss.
- **The data disk is lost (deleted, corrupted):** this is the actual disaster case — SonarQube's live data is gone. Restore from the most recent nightly Blob backup per above. You lose at most ~24h of analysis history/config, never the underlying source code or Git history (those live in Git, untouched).
- **The whole resource group is deleted:** same as above, plus you lose the backup storage account too unless it's the one thing you explicitly excluded from that deletion — this is the one scenario worth thinking about before it happens, not after.

## Limitations (stated plainly, not hidden)

- Backup storage is LRS (locally redundant) — a full Central India region outage takes out the primary VM *and* the backups together. Acceptable for a capstone/dev environment; upgrade to GRS (`account_replication_type = "GRS"` in the module) if this ever needs to survive a regional outage.
- No automated *restore drill* exists — this document is the procedure, but nobody has run it end-to-end yet. Worth doing once, deliberately, before trusting it.
- The OS disk (VM itself) has no backup at all — by design, since it holds no state that isn't reproducible from this Terraform module plus a restore from the last backup.
