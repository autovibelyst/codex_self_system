# <service> Add-on

## Enable
- Add env in `.env`:
  - `TT_<SERVICE>_HOST_PORT=20080`
- Start:
  - `scripts\ttcore.ps1 up profile <service>`

## Access (local)
- `http://localhost:<SERVICE_PORT>/`

## Tunnel
- Default: gets a subdomain if tunnel is enabled.
- To opt-out:
  - set `NO_TUNNEL_<SERVICE>=1` in tunnel env.
