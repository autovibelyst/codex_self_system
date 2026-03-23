# Secret Management — TT-Production v14.0
<!-- Last Updated: v14.0 -->

## Current Posture

TT-Production v14.0 uses **SOPS + age encryption** as the primary secret management mechanism.
Secrets are encrypted at rest in `tt-core/secrets/*.enc.env` using age public-key encryption.
The age private key lives on the operator machine only — never in the repository or package.

### How Secrets Are Protected

| Layer | Mechanism |
|-------|-----------|
| At rest | SOPS + age encryption (`*.enc.env` files) |
| In transit | Docker internal networks (`tt_core_internal`) |
| Access control | `no-new-privileges:true` on all 23+ containers |
| Key storage | age private key: `~/.config/tt-production/age/key.txt` (operator only) |
| Rotation | `bash scripts-linux/rotate-secrets.sh` |

### Secrets Generated at Init

| Variable | Type | Strength |
|----------|------|----------|
| `TT_POSTGRES_PASSWORD` | Random base64 | 32 chars |
| `TT_REDIS_PASSWORD` | Random hex | 32 chars |
| `TT_N8N_ENCRYPTION_KEY` | Random hex | 32 chars |
| `TT_PGADMIN_PASSWORD` | Random base64 | 24 chars |
| `TT_QDRANT_API_KEY` | Random UUID | 36 chars |
| All `*_DB_PASSWORD` vars | Random base64 | 24 chars |

### Bootstrap

```bash
bash tt-core/installer/lib/sops-setup.sh   # install SOPS + age, generate keypair
bash tt-core/scripts-linux/init.sh          # generates and encrypts secrets
bash tt-core/scripts-linux/validate-sops.sh # verify SOPS setup
```

### Migration from v12.x or v13.x (plaintext .env)

```bash
bash tt-core/scripts-linux/migrate-to-sops.sh
```

---

## Key Backup — Critical

The age private key at `~/.config/tt-production/age/key.txt` is the **sole decryption key**.
Loss of this key = encrypted secrets are permanently unrecoverable.

**Required action:** Back up the key to a secure offline location immediately after init.

See `docs/SOPS_GUIDE.md` for complete key management procedures.

---

## Plaintext Fallback (Not Recommended)

Set `secret_mode: "plaintext"` in `config/services.select.json` to use `.env` files directly.
This mode generates a Preflight Check warning and is not recommended for production.

---

*TT-Production v14.0 — Secret Management*
