# TT-Production v14.0

Commercial self-hosted stack with hardened release/export flow, strict image locking, and guided installers for Linux and Windows.

## Quick Install (Linux)

1. Download bootstrap installer:

```bash
curl -fsSL https://raw.githubusercontent.com/<OWNER>/<REPO>/main/install.sh -o install.sh
```

2. Run one command:

```bash
bash install.sh --owner <OWNER> --repo <REPO> --profile local-private --tz UTC
```

Common profiles:
- `local-private`
- `small-business`
- `ai-workstation`
- `public-productivity`

Example with tunnel:

```bash
bash install.sh --owner <OWNER> --repo <REPO> --profile small-business --tz Asia/Riyadh --with-tunnel --domain example.com
```

## Quick Install (Windows PowerShell)

1. Download bootstrap installer:

```powershell
iwr https://raw.githubusercontent.com/<OWNER>/<REPO>/main/install.ps1 -OutFile install.ps1
```

2. Run one command:

```powershell
.\install.ps1 -Owner "<OWNER>" -Repo "<REPO>" -ProfileName "local-private" -Timezone "UTC"
```

Example with tunnel:

```powershell
.\install.ps1 -Owner "<OWNER>" -Repo "<REPO>" -ProfileName "small-business" -Timezone "Asia/Riyadh" -WithTunnel -Domain "example.com"
```

## GitHub Publish (Source Repo)

```powershell
git init
git branch -M main
git add .
git commit -m "TT-Production v14.0 source release"
git remote add origin https://github.com/<OWNER>/<REPO>.git
git push -u origin main
git tag -a v14.0 -m "TT-Production v14.0"
git push origin v14.0
```

Releases should publish these assets:
- `TT-Production-v14.0.zip`
- `TT-Production-v14.0.zip.sha256`

## CI and Release

- CI gate: `bash release/ci-gate.sh --strict`
- Bundle pipeline: `bash release/make-release.sh`
- Source release validator: `pwsh ./tt-core/release/validate-release.ps1`
- Bundle validator: `pwsh ./release/validate-bundle.ps1 -Root ./dist/TT-Production-v14.0`
