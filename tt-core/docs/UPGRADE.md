# Upgrade — TT-Production v14.0 (Windows Quick Reference)

> **Full upgrade procedures** are in [`UPGRADE_GUIDE.md`](UPGRADE_GUIDE.md).  
> This file is the Windows PowerShell quick reference.

---

## Quick Upgrade (Windows)

```powershell
# Step 1: Full backup first — non-negotiable
scripts\backup\Backup-All.ps1

# Step 2: Stop current stack
scripts\Stop-Core.ps1

# Step 3: Copy .env and volumes to new bundle
# (see UPGRADE_GUIDE.md for exact commands)

# Step 4: Start new bundle
scripts\Start-Core.ps1

# Step 5: Verify
scripts\Smoke-Test.ps1
```

## Rollback (Windows)
```powershell
scripts\Stop-Core.ps1
# Restore previous bundle path
scripts\Start-Core.ps1
```

## When to Re-run Init After Upgrade
Re-run `scripts\Init-TTCore.ps1` if the new release introduced:
- new secrets
- new volume directories  
- new env keys

This is safe to re-run — it only fills missing values, never overwrites existing ones.

---

For the complete upgrade matrix, rollback procedure, and acceptance criteria,  
see **[UPGRADE_GUIDE.md](UPGRADE_GUIDE.md)**.
