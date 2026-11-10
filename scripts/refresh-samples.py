#!/usr/bin/env python3
"""Generate bilingual sample catalogs and format guides from checked-in fixtures."""
from argparse import ArgumentParser
from pathlib import Path
import json
import os

parser = ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true', help='Check generated catalogs and guides without writing')
parser.add_argument('--text-only', action='store_true', help='Compatibility alias; fixtures are never overwritten')
parser.add_argument('--refresh-webp', action='store_true', help='Re-encode the two WebP covers (requires Pillow)')
options = parser.parse_args()
if options.check and options.refresh_webp:
    parser.error('--check cannot be combined with --refresh-webp')
root = Path(__file__).resolve().parent.parent
resources = root / 'Sources/Luma/Resources'
entries = json.loads((root / 'Samples/catalog.json').read_text())
outputs = {}
for language in ['en', 'zh-Hans']:
    samples = resources / 'Samples' / language
    catalog = [dict(entry[language], extensions=entry['extensions']) for entry in entries]
    paths = [entry['path'] for entry in catalog]
    extensions = [ext for entry in catalog for ext in entry['extensions']]
    if len(paths) != len(set(paths)) or len(extensions) != len(set(extensions)):
        raise SystemExit(f'Duplicate representative or extension: {language}')
    for path in paths:
        if not (samples / path).is_file():
            raise SystemExit(f'Missing sample: {language}/{path}')
    outputs[resources / f'SampleCatalog-{language}.json'] = json.dumps(catalog, ensure_ascii=False, indent=2) + '\n'
    english = language == 'en'
    guide = samples / ('FormatExamples/FormatGuide.md' if english else '格式示例/格式导览.md')
    lines = [(root / f'Samples/FormatGuide.{language}.md').read_text().rstrip(), '']
    for section in dict.fromkeys(entry['section'] for entry in catalog):
        lines += [f'### {section}', '', '| Format / Language | Extensions | Example |' if english else '| 格式 / 语言 | 扩展名 | 示例文件 |', '| --- | --- | --- |']
        for entry in catalog:
            if entry['section'] != section:
                continue
            relative = os.path.relpath(samples / entry['path'], guide.parent)
            suffixes = ', '.join(f'`.{ext}`' for ext in entry['extensions']) or ('Detected as text' if english else '按文本内容识别')
            lines.append(f"| {entry['name']} | {suffixes} | [{Path(entry['path']).name}](<{relative}>) |")
        lines.append('')
    outputs[guide] = '\n'.join(lines)
    if options.refresh_webp:
        from PIL import Image
        cover = samples / ('ReadingCover.png' if english else '留白.png')
        target = samples / ('ImageFormats/ReadingCover.webp' if english else '图片格式/阅读封面.webp')
        with Image.open(cover) as image:
            image.save(target, format='WEBP', lossless=True)
stale = []
for path, content in outputs.items():
    if options.check:
        if not path.exists() or path.read_text() != content:
            stale.append(str(path.relative_to(root)))
    else:
        path.write_text(content)
if stale:
    raise SystemExit('Run python3 scripts/refresh-samples.py:\n' + '\n'.join(stale))
print(f'{"Checked" if options.check else "Generated"} two catalogs: {len(entries)} formats and {len(extensions)} extensions each.')
