# Ports (TT-Supabase)

Host published (default):
- Kong HTTP: 127.0.0.1:18000 -> 8000 (container)
- Kong HTTPS: 127.0.0.1:18443 -> 8443 (container)

Optional:
- Supavisor transaction pooler: 127.0.0.1:16543 -> 6543

Not published on host (container-only):
- Postgres: 5432/tcp (inside docker network only)
