# TT-Core — Production Runtime and Update Model (TT-Production v14.0)

TT-Core is the primary runtime stack inside the TT-Production commercial bundle.

## Runtime root
- Windows: `%USERPROFILE%\stacks\tt-core`
- Linux/macOS: operator-chosen stable path

## What this folder contains
- compose definitions for the core stack and add-ons
- operational scripts for Windows and Linux/macOS
- environment templates
- installer and release validation assets
- policy and selection files for controlled deployments

## Declarative install inputs
Two files define controlled deployment intent:
- `config/services.select.json` → service defaults, tunnel intent, customer profile
- `config/public-exposure.policy.json` → allowed public-capable services and tunnel rule mapping

## Update and locking workflow
This bundle supports a safe update workflow using:
- `scripts/Update-TTCore.ps1`
- `scripts/Lock-ComposeImages.ps1`
- `scripts/Show-ComposeImages.ps1`

The goal is to preserve reproducibility while keeping future updates manageable.


## Production Governance Model
- `config/service-catalog.json` is a metadata registry for TT-Core services.
- `scripts/Preflight-Check.ps1` should be run before first runtime acceptance to validate env readiness and route/profile consistency.
- Execution source-of-truth remains unchanged: `services.select.json` drives install choices and `public-exposure.policy.json` governs public exposure rules.
