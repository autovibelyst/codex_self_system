# Authority Model — TT-Production v14.0

This document defines source-of-truth boundaries for configuration, generation, and runtime secrets.

---

## Class 1: Canonical Authority (human-edited)

| File | Authority Over |
|------|----------------|
| `release/version.json` | Product identity and version metadata only |
| `tt-core/config/service-catalog.json` | Service metadata and exposure tiers |
| `tt-core/config/services.select.json` | Operator intent (profiles/routes/security acknowledgments) |
| `tt-core/env/.env.example` | Core operator env template |
| `tt-core/env/tunnel.env.example` | Tunnel operator env template |

---

## Class 2: Generated Files (never hand-edit)

| File | Generator |
|------|-----------|
| `tt-core/config/public-exposure.policy.json` | release generators |
| `release/exposure-summary.*` | release generators |
| `release/signoff.json` | release pipeline |
| `release/bundle-manifest.json` | release pipeline |

---

## Class 3: Runtime-Only Secret Files (external)

These files are not source-of-truth for policy and must not live in repository paths.

| File | Purpose |
|------|---------|
| `${XDG_CONFIG_HOME:-$HOME/.config}/tt-production/runtime/<stack>/core.env` | Live core runtime env/secrets |
| `${XDG_CONFIG_HOME:-$HOME/.config}/tt-production/runtime/<stack>/tunnel.env` | Tunnel token/runtime tunnel vars |

`CF_TUNNEL_TOKEN` must only be in runtime tunnel env.

---

## Tunnel Authority Chain

```
Operator intent:  config/services.select.json
        ↓
URL derivation scripts (Update-TunnelURLs)
        ↓
Runtime writes:   runtime/<stack>/core.env
```

Token path is separate and runtime-only: `runtime/<stack>/tunnel.env`.

---

## Anti-Patterns

- Editing generated files by hand.
- Keeping runtime secrets inside repository paths.
- Using runtime env as policy source instead of `services.select.json`.
- Placing `CF_TUNNEL_TOKEN` in core runtime env.