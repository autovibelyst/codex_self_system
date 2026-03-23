# Restricted Admin Exposure Guide — TT-Production v14.0

## What Are Restricted Admin Services?

These services grant elevated or complete control over the stack:

| Service | Risk Level | What It Controls |
|---------|-----------|-----------------|
| pgAdmin | HIGH | Full PostgreSQL administrative control over ALL databases |
| Portainer | CRITICAL | Root-equivalent Docker daemon access to the host OS |
| OpenClaw | HIGH | Broad automation and script execution permissions |

## The Double-Gate Model

Exposing any of these services via Cloudflare Tunnel requires TWO independent actions:

### Gate 1 — services.select.json
```json
{
  "security": {
    "allow_restricted_admin_tunnel_routes": true
  }
}
```

### Gate 2 — config/security-ack.json
Fill the template at `tt-core/config/security-ack.json`:
```json
{
  "operator_name": "Your Name",
  "operator_email": "you@example.com",
  "hostname": "your-server-hostname",
  "acknowledged_at": "2026-03-14T12:00:00Z",
  "services_acknowledged": ["pgadmin"],
  "signature": "<computed by verify-security-ack.sh>"
}
```
Then generate the signature:
```bash
bash tt-core/scripts-linux/verify-security-ack.sh --generate-signature
```

## Verification

Both gates are checked by Preflight Check #23:
```bash
bash tt-core/scripts-linux/preflight-check.sh
```
And directly:
```bash
bash tt-core/scripts-linux/verify-security-ack.sh
```

## Recommendations

1. **Do not expose Portainer via tunnel** — use local access only
2. If you must expose pgAdmin: put Cloudflare Access in front of it
3. Rotate admin passwords monthly if exposed
4. Monitor access logs via Cloudflare Analytics
