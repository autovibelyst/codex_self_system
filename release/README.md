# TT-Production Bundle Release Assets

This folder contains bundle-level release validation for the commercial package.
Run `validate-bundle.ps1` before final delivery or before declaring a modified bundle production-ready.

## CI Gate (new)

Use `release/ci-gate.sh` in source CI pipelines for quality and security checks.

Examples:
- `bash release/ci-gate.sh`
- `bash release/ci-gate.sh --strict`
- `TT_ALLOW_RUNTIME_ENV=1 bash release/ci-gate.sh --strict` (local dev only)

The gate writes `release/ci-gate-report.txt` and returns non-zero when a blocking stage fails.
