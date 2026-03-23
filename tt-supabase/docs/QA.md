# QA (TT-Supabase)

## Smoke checks
1) Kong reachable:
   - http://127.0.0.1:18000/project/default

2) PostgREST should respond (requires API key):
   - add header apikey: <ANON_KEY>

3) Pooler (if enabled):
   - TCP connect to 127.0.0.1:16543

## Expected behavior
- Direct GET to /rest/v1 without key returns: "No API key found" (this is OK).
