# TT-Core / TT-Supabase — ENV & Secrets Strategy

> **Version:** TT-Production v14.0

This document defines the environment authority model for TT-Production.

---

## Core Principle

**Templates are committed. Runtime env files are external and never committed.**

- `.env.example` files = templates with placeholders. Committed. No real secrets.
- Runtime env files = live configuration and secrets. External path. Never committed.

---

## TT-Core Model

### File 1 — Operator Template (EDIT THIS)

```
tt-core/env/.env.example
```

Fill client placeholders, keep `__GENERATE__` values for init.

### File 2 — Runtime Core Env (DO NOT KEEP IN REPO)

```
${XDG_CONFIG_HOME:-$HOME/.config}/tt-production/runtime/<stack>/core.env
```

- Written/maintained by init scripts.
- Used by Docker Compose at runtime.
- If a legacy `compose/tt-core/.env` exists, scripts migrate/resolve it.

### Runtime Flow

```
Operator edits:   tt-core/env/.env.example
          ↓
Init/Installer resolves runtime path
          ↓
Runtime uses:    .../runtime/<stack>/core.env
```

---

## Tunnel Runtime Env

Template:

```
tt-core/env/tunnel.env.example
```

Runtime file:

```
${XDG_CONFIG_HOME:-$HOME/.config}/tt-production/runtime/<stack>/tunnel.env
```

`CF_TUNNEL_TOKEN` must live only in runtime tunnel env.

---

## TT-Supabase

Supabase continues with its own env template/runtime flow under `tt-supabase`.

---

## Security Rules

1. Never commit runtime env files.
2. Never hardcode secrets in compose or scripts.
3. Re-run init safely: existing secrets are not overwritten.
4. On upgrades, compare new templates with runtime env and add missing keys.