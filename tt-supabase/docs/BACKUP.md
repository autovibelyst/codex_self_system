# Backup (TT-Supabase)

Back up Supabase separately from TT-Core.

## Files to include
- compose/tt-supabase/**
- compose/tt-supabase/.env (secrets!)
- volumes:
  - compose/tt-supabase/volumes/db (postgres data)  [largest]

## Options
A) Full snapshot (recommended for migration): zip entire stack directory excluding cache/temp.
B) Logical backup (advanced): pg_dump from inside db container.
