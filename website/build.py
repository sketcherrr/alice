#!/usr/bin/env python3
"""Build the public introduction page, copying only explicitly listed assets."""
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'dist' / 'site'
OUT.mkdir(parents=True, exist_ok=True)
for name in ('index.html', 'style.css', 'app.js', 'favicon.svg'):
    shutil.copyfile(ROOT / 'website' / name, OUT / name)
(OUT / '.nojekyll').touch()
(OUT / 'assets').mkdir(exist_ok=True)
shutil.copyfile(ROOT / 'assets/characters/alice/idle.png', OUT / 'assets/alice.png')
for name in ('calm', 'social', 'activities'):
    shutil.copyfile(ROOT / f'assets/characters/alice/animations/{name}.png', OUT / f'assets/{name}.png')
print(f'Website built: {OUT}')
