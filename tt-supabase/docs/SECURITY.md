# Security (TT-Supabase)

- DB is not published to host by default.
- Only Kong is published to 127.0.0.1 (loopback).
- For internet exposure use Cloudflare Tunnel with Access policies.
- Keep env secrets out of Git; use env file per stack.
