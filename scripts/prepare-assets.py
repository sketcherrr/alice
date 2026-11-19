#!/usr/bin/env python3
"""Copy original art into the Flutter bundle without altering its alpha channel."""
from pathlib import Path
import shutil

root = Path(__file__).resolve().parents[1]
target = root / 'apps/companion/assets'
target.mkdir(parents=True, exist_ok=True)
shutil.copy2(root / 'assets/characters/alice/idle.png', target / 'character.png')
shutil.copytree(root / 'assets/characters/alice/animations', target / 'animations', dirs_exist_ok=True)
shutil.copytree(root / 'assets/audio', target / 'audio', dirs_exist_ok=True)
for filename in ('NotoSansCJKsc-Regular.otf', 'OFL.txt'):
    shutil.copy2(root / 'assets/fonts' / filename, target / filename)
print('Character artwork staged.')
