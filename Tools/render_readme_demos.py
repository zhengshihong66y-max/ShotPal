#!/usr/bin/env python3
"""Export compact looping README demos while retaining the approved title artwork."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'docs/assets/github'
KEYS = ('download', 'scene', 'capture', 'audio', 'subtitle', 'storyboard', 'drag', 'music')

for language in ('en', 'zh-CN'):
    output = ASSETS / 'demos' / language
    output.mkdir(parents=True, exist_ok=True)
    for key in KEYS:
        version = 2 if key == 'drag' else 1
        source = ASSETS / 'showcase' / f'shotpal-showcase-{key}-en-1440-25fps-v{version}.gif'
        poster = (ASSETS / 'zh-CN/posters' / f'{key}.png' if language == 'zh-CN'
                  else ASSETS / 'showcase/posters' / f'{key}.webp')
        # Reuse the approved SF/PingFang title pixels; animate only the original demo.
        graph = ('[1:v]crop=1440:320:0:0[title];'
                 '[0:v][title]overlay=0:0:shortest=1,fps=10,scale=1100:825:flags=lanczos,split[a][b];'
                 '[a]palettegen=max_colors=128:stats_mode=diff[p];'
                 '[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle[out]')
        target = output / f'{key}.gif'
        subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
                        '-ignore_loop', '1', '-i', str(source), '-loop', '1', '-i', str(poster),
                        '-filter_complex', graph, '-map', '[out]', '-t', '7', '-loop', '0',
                        str(target)], check=True)
        print(f'{language}/{key}: {target.stat().st_size:,} bytes', flush=True)
