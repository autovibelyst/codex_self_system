# SOPS + age Secret Management Guide - TT-Production v14.0

## Overview

TT-Production v14.0 uses **SOPS** (Secrets Operations) with **age** encryption as
the official hardened secret mode. Secrets are encrypted at rest in the repository;
decryption requires an age private key that lives only on the operator's machine.

## How It Works

```
Operator machine                     Repository (safe to commit)
------------------                   --------------------------
~/.config/tt-production/             tt-core/secrets/
  age/key.txt        <-decrypt--   core.secrets.enc.env   (SOPS-encrypted)
  (PRIVATE KEY)      --encrypt-->   tunnel.secrets.enc.env (SOPS-encrypted)
```

## Initial Setup

```bash
# 1. Bootstrap SOPS and age
bash tt-core/installer/lib/sops-setup.sh

# 2. Initialize secrets (generates and encrypts)
bash tt-core/scripts-linux/init.sh

# 3. Verify
bash tt-core/scripts-linux/validate-sops.sh
```

## Decrypt for Docker Compose

```bash
# Decrypt to the external runtime directory (required before starting services)
TT_RUNTIME_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tt-production/runtime/tt-core"
mkdir -p "$TT_RUNTIME_DIR"
sops --decrypt tt-core/secrets/core.secrets.enc.env > "$TT_RUNTIME_DIR/core.env"
sops --decrypt tt-core/secrets/tunnel.secrets.enc.env > "$TT_RUNTIME_DIR/tunnel.env"
chmod 600 "$TT_RUNTIME_DIR/core.env" "$TT_RUNTIME_DIR/tunnel.env"

# Or use start-core.sh which handles this automatically
bash tt-core/scripts-linux/start-core.sh
```

## Rotating a Secret

```bash
# Low-risk secrets (no DB changes required)
bash tt-core/scripts-linux/rotate-secrets.sh --secret TT_PGADMIN_PASSWORD

# High-risk secrets (requires DB ALTER USER)
# See docs/CREDENTIAL_ROTATION.md
```

## Key Backup

**CRITICAL:** Back up your age private key. If lost, encrypted secrets cannot be recovered.

```bash
# Your private key location
cat ~/.config/tt-production/age/key.txt

# Backup securely (offline storage, password manager, etc.)
cp ~/.config/tt-production/age/key.txt /your/secure/backup/location
```

## Migration from v13.0 (Plaintext .env)

```bash
bash tt-core/scripts-linux/init.sh --migrate-from-plaintext
```

This reads the existing runtime env, encrypts all secrets to SOPS format, and moves
legacy in-repo plaintext files out of the repository path.

## Fallback Mode (Not Recommended)

If SOPS is unavailable (air-gapped, temporary), set in services.select.json:
```json
{ "client": { "secret_mode": "plaintext" } }
```
This suppresses SOPS preflight warnings but leaves secrets unencrypted.