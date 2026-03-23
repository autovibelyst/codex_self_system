# Backup & Restore Guide — TT-Production v14.0
<!-- Last Updated: v14.0 -->

TT-Core ships with a complete backup/restore/rollback system with AES-256-CBC encryption,
SHA-256 checksums, strict dry-restore verification, and optional offsite upload to
S3/Wasabi/Cloudflare R2.

---

## Quick Backup

### Linux/macOS
```bash
cd tt-core
bash scripts-linux/backup.sh
```

### Windows
```powershell
cd tt-core
.\scripts\backup\Backup-All.ps1
```

---

## Backup Scope

| Component | What is backed up |
|-----------|------------------|
| PostgreSQL | `postgres/*.dump` (`pg_dump -Fc`) or `postgres/*.dump.enc` when `TT_BACKUP_ENCRYPTION_KEY` is set |
| WordPress / MariaDB | `wordpress.sql` when MariaDB is running and WordPress root credentials are available |
| Volumes | `volumes-<timestamp>.tar.gz` for bind-mounted service data (with large runtime paths excluded) |
| Runtime env snapshot | `.env.backup` copied from the resolved runtime env path |
| Metadata | `backup-manifest.txt` and `checksums.sha256` |

**Not included in automated backup:**
- Container images (pulled from registry)
- Age private key (`~/.config/tt-production/age/key.txt`)

---

## Scheduled Backup Setup

### Linux/macOS
```bash
bash scripts-linux/setup-backup-schedule.sh
```
Adds a daily cron job at 2:00 AM.

### Windows
```powershell
.\scripts\backup\Setup-Backup-Schedule.ps1
```
Creates a Windows Scheduled Task: **"TT-Core Daily Backup"** at 2:00 AM.

---

## Verify Backup Integrity

### Linux/macOS
```bash
cd backups/backup_<timestamp>
sha256sum -c checksums.sha256
```

`checksums.sha256` covers PostgreSQL dumps, encrypted dump artifacts, SQL exports,
and volume archives. The strict verifier also checks these automatically.

### Windows
```powershell
cd backups\backup_<timestamp>
Get-Content checksums.sha256 | ForEach-Object {
    $hash, $file = $_ -split '  '
    $actual = (Get-FileHash $file -Algorithm SHA256).Hash.ToLower()
    if ($actual -eq $hash) { "OK: $file" } else { "FAIL: $file" }
}
```

---

## Restore

### Linux/macOS
```bash
bash scripts-linux/restore.sh --backup-dir backups/backup_<timestamp> --confirm
```

### Windows (Full Restore)
```powershell
.\scripts\backup\Restore-All.ps1 -SnapshotPath ".\backups\backup_<timestamp>"
```

### Windows (Manual)
```powershell
.\scripts\backup\Restore-PostgresDump.ps1 -SnapshotPath ".\backups\backup_<timestamp>"
```

---

## Rollback

### Linux/macOS
```bash
# List available snapshots
bash scripts-linux/rollback.sh --list

# Roll back to a specific snapshot
bash scripts-linux/rollback.sh --snapshot backups/backup_<timestamp>
```

### Windows
Rollback is not shipped as a dedicated PowerShell wrapper in the commercial bundle.
Use a validated backup plus `Restore-All.ps1` / `Restore-PostgresDump.ps1`.

---

## Offsite Backup (S3 / Wasabi / Cloudflare R2)

### Linux/macOS
```bash
bash scripts-linux/backup-offsite.sh
```

Configure in `.env`:
```env
TT_OFFSITE_REMOTE=s3:your-bucket/tt-core-backups
TT_RCLONE_REMOTE_NAME=myremote
```

### Windows
Set the same `TT_OFFSITE_REMOTE` in `.env` and run:
```powershell
.\scripts\backup\Backup-Offsite.ps1
```

---

## Backup Retention

### Linux/macOS
```bash
bash scripts-linux/cleanup-backups.sh --keep 7
```

### Windows
```powershell
.\scripts\backup\Cleanup-Backups.ps1 -KeepCount 7
```

---

## Verify Restore (Post-restore validation)

### Linux/macOS
```bash
bash scripts-linux/verify-restore.sh --backup-dir backups/backup_<timestamp>
```

What `verify-restore.sh` does in strict mode:
- Verifies `checksums.sha256`
- Validates PostgreSQL dump artifacts from `postgres/*.dump` and `postgres/*.dump.enc`
- Decrypts encrypted dumps only into a temporary directory
- Runs `pg_restore --schema-only --clean --if-exists -Fc` in a disposable `postgres:16.6-alpine` container
- Imports `wordpress.sql` into a disposable `mariadb:11.8.6` container when present

If encrypted dumps exist, `TT_BACKUP_ENCRYPTION_KEY` must be set in the resolved runtime env
before verification or restore.

### Windows
```powershell
# Run smoke test after restore
bash scripts-linux/smoke-test.sh   # via WSL2 or Git Bash
```

---

*TT-Production v14.0 — Backup Guide — docs/BACKUP.md*
