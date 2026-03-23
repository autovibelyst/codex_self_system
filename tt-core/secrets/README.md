# TT-Production Secrets Directory

## What lives here

| File | Type | Committed to git? |
|------|------|--------------------|
| `core.secrets.enc.env` | SOPS-encrypted with age | No - generated per operator/runtime |
| `tunnel.secrets.enc.env` | SOPS-encrypted with age | No - generated per operator/runtime |
| `.sops.yaml` | SOPS config (public key ref) | Yes |
| `*.env` | Plaintext runtime secrets | No - never store them in this directory or the repo tree |

## Setup

Run `bash tt-core/installer/lib/sops-setup.sh` to generate your age keypair and
prepare encrypted secrets for this operator environment. The age PRIVATE key lives at
`~/.config/tt-production/age/key.txt` on your machine and must never be shipped.

## Runtime decryption target

Decrypt secrets only into the external runtime directory managed by the helper scripts:

```bash
TT_RUNTIME_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tt-production/runtime/tt-core"
mkdir -p "$TT_RUNTIME_DIR"
sops --decrypt tt-core/secrets/core.secrets.enc.env > "$TT_RUNTIME_DIR/core.env"
sops --decrypt tt-core/secrets/tunnel.secrets.enc.env > "$TT_RUNTIME_DIR/tunnel.env"
chmod 600 "$TT_RUNTIME_DIR/core.env" "$TT_RUNTIME_DIR/tunnel.env"
```

If you use `init.sh` or `start-core.sh`, they resolve these runtime files automatically and
migrate any legacy in-repo `.env` file out of the repository.

The source package must keep `.sops.yaml` with `<OPERATOR_AGE_PUBLIC_KEY>` placeholder only.
Do not commit operator-specific encrypted secret payloads into the repository.

See `tt-core/docs/SOPS_GUIDE.md` for the full operator workflow.
