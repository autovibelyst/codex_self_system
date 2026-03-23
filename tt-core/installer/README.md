# TT-Core Installer

Installers:
- `Install-TTCore.sh` (Linux)
- `Install-TTCore.ps1` (Windows)

## Runtime target
- default runtime path: `%USERPROFILE%\stacks\tt-core`

## Declarative input
Before installation, review:
- `..\config\services.select.json`

The installer reads this file as the primary input for:
- optional profiles
- tunnel defaults
- customer identity metadata

Explicit PowerShell parameters override the file when supplied.

## Preset profiles
Both installers support deployment presets:
- `local-private`
- `small-business`
- `ai-workstation`
- `public-productivity`

Linux example:
```bash
bash installer/Install-TTCore.sh --profile local-private --tz UTC
```

Windows example:
```powershell
.\Install-TTCore.ps1 -ProfileName "local-private" -Timezone "UTC"
```
