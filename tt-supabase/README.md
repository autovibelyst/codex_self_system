# TT-Supabase (Production Bundle Companion)

TT-Supabase is the optional standalone Supabase stack shipped alongside TT-Production.
It is not part of the TT-Core baseline runtime.

## Runtime path
- Windows: `%USERPROFILE%\stacks\tt-supabase`
- Linux: operator-chosen stable path

## What’s included
- Supabase services (db, auth, rest, realtime, storage, functions, studio, kong gateway, analytics, vector)
- Optional Supavisor pooler (transaction mode)
- Independent scripts: start/stop/status/logs/diagnostics + smoke test
- Independent docs: ports, backup, upgrade, security, QA

## Default exposure rules
- Only **Kong** is published on host by default: `127.0.0.1:18000 -> 8000`
- Kong HTTPS is optional
- Database is **not** published on host by default
- Pooler is optional and published only when explicitly enabled

## Commercial positioning
- shipped in the same product bundle
- operationally independent from TT-Core
- can be delivered or omitted depending on the customer scope
