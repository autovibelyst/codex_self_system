# Adding a New Service to TT-Core  (TT-Production v14.0)

This guide explains how to add a new optional service as a TT-Core add-on without breaking the production authority model.

---

## Step 1: Create the addon compose file

Create `compose/tt-core/addons/NN-servicename.addon.yml`.

Use `templates/addon.service.template.yml` as a starting point.

**Rules:**
- Always use `profiles: ["yourprofile"]`
- Pin the image version — never use `:latest`
- Use bind-mount volumes under `./volumes/servicename/`
- Attach to `tt_core_internal` for internal access and `tt_shared_net` only if the service needs a UI / tunnel reachability
- Keep ports bound through `${TT_BIND_IP}` rather than `0.0.0.0`

**Example:**
```yaml
services:
  myservice:
    profiles: ["myservice"]
    container_name: tt-core-myservice
    image: vendor/myservice:1.2.3
    restart: unless-stopped
    environment:
      TZ: ${TT_TZ}
      MY_VAR: ${TT_MYSERVICE_VAR}
    ports:
      - "${TT_BIND_IP}:${TT_MYSERVICE_HOST_PORT}:8080"
    volumes:
      - ./volumes/myservice/data:/app/data
    networks:
      - tt_core_internal
      - tt_shared_net

networks:
  tt_core_internal:
    external: true
  tt_shared_net:
    external: true
```

---

## Step 2: Add environment variables

In `env/.env.example`, add the variables needed by the service:
```env
TT_MYSERVICE_HOST_PORT=18099
TT_MYSERVICE_VAR=some-value
```

---

## Step 3: Register the profile

Update the profile helpers so the service can be started intentionally:
- `scripts/_profiles.ps1`
- any matching Linux/profile helper if the service is supported there

Add the profile to the all-profiles list and to the service-to-profile mapping.

---

## Step 4: Create volume directories

Update the init workflow so first-run initialization creates the new bind-mount paths.
At minimum review:
- `scripts/Init-TTCore.ps1`
- `scripts-linux/init.sh`

---

## Step 5: Register the service in the canonical catalog

If the service is part of the supported product surface, add it to:
- `config/service-catalog.json`

Then regenerate compatibility policy data:
- `scripts/Sync-PublicExposurePolicy.ps1`

This keeps `service-catalog.json` as the canonical metadata source and prevents drift between service metadata and public exposure policy.

---

## Step 6: Optional tunnel exposure

TT-Production uses **token-only Tunnel runtime**. Do **not** add new services through legacy ingress template files.

If the service may be publicly reachable:
1. Mark the service correctly in `config/service-catalog.json`
2. Regenerate `config/public-exposure.policy.json`
3. Review the effective exposure with `scripts/Show-TunnelPlan.ps1`
4. Only then configure the hostname on the Cloudflare side

Restricted admin services must stay opt-in and require explicit policy approval.

---

## Step 7: Optional database provisioning

If the service needs its own Postgres database:
1. Add the env variable to `env/.env.example`
2. Update the postgres service environment if needed
3. Extend the Postgres init script so the database is created idempotently

Keep database exposure internal-only unless there is a strong operational reason otherwise.

---

## Step 8: Update documentation

Review and update the user-facing docs so runtime and docs stay aligned:
- `docs/SERVICES.md`
- `docs/PORTS.md`
- `README_ADDONS.md`
- any release checklist or smoke-test notes affected by the new service

---

## Step 9: Validate

Recommended validation flow:
```powershell
release\validate-bundle.ps1
tt-core\release\validate-release.ps1
tt-core\scripts\Preflight-Check.ps1
# Or on Linux/macOS:
bash release/consistency-gate.sh
bash tt-core/scripts-linux/preflight-check.sh
```

Then start only the intended profile and verify logs, ports, health, and rollback behavior.
