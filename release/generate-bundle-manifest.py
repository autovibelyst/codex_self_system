#!/usr/bin/env python3
import argparse
import datetime as dt
import json
from pathlib import Path
import subprocess


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description='Generate a truthful TT-Production bundle manifest.')
    parser.add_argument('--root', required=True, help='Bundle root directory to scan.')
    parser.add_argument('--output', required=True, help='Path to write bundle-manifest.json.')
    parser.add_argument('--version', default='', help='Package version override.')
    parser.add_argument('--bundle-name', default='', help='Bundle root folder name override.')
    parser.add_argument(
        '--required-root-file',
        action='append',
        default=[],
        dest='required_root_files',
        help='Root-level file that must exist in the commercial bundle. May be passed multiple times.',
    )
    return parser.parse_args()


def detect_version(bundle_root: Path, explicit_version: str) -> str:
    if explicit_version:
        return explicit_version
    version_path = bundle_root / 'release' / 'version.json'
    if version_path.is_file():
        try:
            data = json.loads(version_path.read_text(encoding='utf-8'))
            for key in ('package_version', 'tt_version', 'version'):
                value = str(data.get(key, '')).strip()
                if value:
                    return value
        except json.JSONDecodeError:
            pass
    return 'unknown'


def load_git_tracked_paths(bundle_root: Path) -> set[str] | None:
    git_dir = bundle_root / '.git'
    if not git_dir.exists():
        return None

    try:
        proc = subprocess.run(
            ['git', '-C', str(bundle_root), 'ls-files', '-z'],
            check=True,
            capture_output=True,
        )
    except (FileNotFoundError, subprocess.CalledProcessError):
        return None

    tracked: set[str] = set()
    for raw in proc.stdout.split(b'\0'):
        if not raw:
            continue
        tracked.add(raw.decode('utf-8', errors='surrogateescape').replace('\\', '/'))
    return tracked


def collect_entries(bundle_root: Path, output_path: Path, tracked_paths: set[str] | None) -> list[dict[str, object]]:
    entries: list[dict[str, object]] = []
    for path in sorted(bundle_root.rglob('*')):
        if not path.is_file():
            continue
        if path.resolve() == output_path.resolve():
            continue
        rel = path.relative_to(bundle_root).as_posix()
        if tracked_paths is not None and rel not in tracked_paths:
            continue
        entries.append({'path': rel, 'size': path.stat().st_size})
    return entries


def build_manifest(
    *,
    version: str,
    bundle_name: str,
    generated_at: str,
    required_root_files: list[str],
    entries: list[dict[str, object]],
) -> dict[str, object]:
    total_files = len(entries)
    return {
        '_schema': 'tt-bundle-manifest/v2',
        '_generator': 'release/generate-bundle-manifest.py',
        '_note': 'Generated from the finalized commercial bundle tree.',
        'package_version': version,
        'tt_version': version,
        'version': version,
        'bundle_name': bundle_name,
        'bundle_root': bundle_name,
        'generated_at': generated_at,
        'total_files': total_files,
        'file_count': total_files,
        'required_root_files': required_root_files,
        'files': entries,
    }


def main() -> int:
    args = parse_args()
    bundle_root = Path(args.root).resolve()
    output_path = Path(args.output).resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)

    version = detect_version(bundle_root, args.version)
    bundle_name = args.bundle_name or bundle_root.name
    generated_at = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace('+00:00', 'Z')

    tracked_paths = load_git_tracked_paths(bundle_root)
    base_entries = collect_entries(bundle_root, output_path, tracked_paths)
    rel_output = output_path.relative_to(bundle_root).as_posix()
    required_root_files = sorted(dict.fromkeys(args.required_root_files))

    manifest_size = 0
    serialized = ''
    for _ in range(10):
        entries = list(base_entries)
        entries.append({'path': rel_output, 'size': manifest_size})
        manifest = build_manifest(
            version=version,
            bundle_name=bundle_name,
            generated_at=generated_at,
            required_root_files=required_root_files,
            entries=entries,
        )
        candidate = json.dumps(manifest, indent=2, ensure_ascii=False) + '\n'
        new_size = len(candidate.encode('utf-8'))
        serialized = candidate
        if new_size == manifest_size:
            break
        manifest_size = new_size
    else:
        raise RuntimeError('Manifest size failed to converge while self-describing output entry.')

    output_path.write_text(serialized, encoding='utf-8', newline='\n')
    actual_size = output_path.stat().st_size
    if actual_size != manifest_size:
        raise RuntimeError(f'Manifest self-size mismatch: expected {manifest_size}, wrote {actual_size}')

    return 0


if __name__ == '__main__':
    raise SystemExit(main())
