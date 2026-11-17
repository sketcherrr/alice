#!/usr/bin/env python3
"""Prepare the reviewed build inputs for a macOS runner; this is NOT a runnable app."""
from pathlib import Path
import hashlib
import json
import zipfile

root = Path(__file__).resolve().parents[1]
output = root / 'dist' / 'Alice-macOS-build-input.zip'
# Explicit allowlist excludes credentials, user saves, local SDK paths and generated binaries.
files = {root / n for n in (
    'Cargo.toml', 'Cargo.lock', '.gitignore', 'README.md',
    'apps/companion/pubspec.yaml', 'apps/companion/pubspec.lock',
    'apps/companion/.metadata', '.github/workflows/macos-test.yml',
)}
for folder in ('crates/pet_core', 'assets', 'docs', 'scripts',
               'apps/companion/lib', 'apps/companion/test', 'apps/companion/macos'):
    for p in (root / folder).rglob('*'):
        if not p.is_file() or p.is_symlink():
            continue
        rel = p.relative_to(root)
        if any(part in {'ephemeral', 'xcuserdata', 'build', '__pycache__', '.DS_Store'} for part in rel.parts):
            continue
        if p.name.startswith('.env') or p.suffix in {'.sqlite3', '.db', '.pyc'}:
            continue
        files.add(p)
manifest = {
    'kind': 'macOS build input; not an application',
    'workflow': '.github/workflows/macos-test.yml',
    'expected_artifact': 'dist/Alice-macOS-universal-test.zip',
    'files': {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)},
}
output.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for p in sorted(files):
        archive.write(p, 'Alice/' + str(p.relative_to(root)))
    archive.writestr('Alice/BUILD_INPUT_MANIFEST.json', json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
checksum = hashlib.sha256(output.read_bytes()).hexdigest()
output.with_suffix('.zip.sha256').write_text(checksum + '  ' + output.name + '\n')
print(f'Build inputs only: {output} ({output.stat().st_size / 1024 / 1024:.1f} MiB, {len(files)} files)')
