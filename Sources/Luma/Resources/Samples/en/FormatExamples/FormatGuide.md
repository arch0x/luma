# File Format Guide

This is the **2026.11.3 English sample collection** for Luma 0.9.0. Each format or language has one representative file; equivalent filename extensions share a row.

## Try these first

- [Markdown preview](../MarkdownPreview.md): expand tables and diagrams, and copy highlighted code.
- [Source editing](../SourceEditing.md): inspect colors, timestamps, byte sizes and escaped strings, then explicitly replace a selection.
- [Standalone SVG](<../ImageAssets/Reading Flow.svg>): zoom, fit to window, use natural text size, and switch to source.
- [JSONC](ReadingSettings.jsonc): preview comments and trailing commas without rewriting the source.
- [JSONL](ReadingLog.jsonl) / [NDJSON](FileEvents.ndjson): read individual records with original line numbers and per-record error messages.
- [CSV](../ReadingList.csv) / [TSV](ReadingProgress.tsv): filter, sort, inspect empty values and numeric ranges; double-click a cell to read its full content.
- [Vue](ReadingCard.vue) / [Svelte](ReadingCard.svelte): highlight template, script and style sections.
- [.gitignore](../CodeAndConfig/.gitignore) / [.env](../CodeAndConfig/.env): inspect rules and key-value syntax.
- [Custom-extension text](Workspace.luma-note): detect UTF-8 text and preserve its extension when saving.

Code and configuration examples support source editing. HTML, components, scripts and patches are read as files. GeoJSON uses JSON preview; GIF displays its first frame. Formatting affects only the preview: saving preserves source comments, line breaks and record structure.

[Return to Welcome](../Welcome.md) for navigation, search, bookmarks and editing examples.

## Complete format list

Extensions on the same row share a reader. Each image encoding is a real file.

### Documents and Data

| Format / Language | Extensions | Example |
| --- | --- | --- |
| Markdown | `.md`, `.markdown`, `.mdown` | [Welcome.md](<../Welcome.md>) |
| PDF | `.pdf` | [ReadingSpace.pdf](<../ReadingSpace.pdf>) |
| SVG | `.svg` | [Reading Flow.svg](<../ImageAssets/Reading Flow.svg>) |
| JSON | `.json` | [Project.json](<../Project.json>) |
| GeoJSON | `.geojson` | [ReadingLocation.geojson](<ReadingLocation.geojson>) |
| JSONC | `.jsonc` | [ReadingSettings.jsonc](<ReadingSettings.jsonc>) |
| JSONL | `.jsonl` | [ReadingLog.jsonl](<ReadingLog.jsonl>) |
| NDJSON | `.ndjson` | [FileEvents.ndjson](<FileEvents.ndjson>) |
| CSV | `.csv` | [ReadingList.csv](<../ReadingList.csv>) |
| TSV | `.tsv` | [ReadingProgress.tsv](<ReadingProgress.tsv>) |
| reStructuredText | `.rst` | [ReadingGuide.rst](<../CodeAndConfig/ReadingGuide.rst>) |

### Images

| Format / Language | Extensions | Example |
| --- | --- | --- |
| PNG | `.png` | [ReadingCover.png](<../ReadingCover.png>) |
| JPEG | `.jpg`, `.jpeg` | [ReadingCover.jpg](<../ImageFormats/ReadingCover.jpg>) |
| GIF | `.gif` | [ReadingCover.gif](<../ImageFormats/ReadingCover.gif>) |
| HEIC / HEIF | `.heic`, `.heif` | [ReadingCover.heic](<../ImageFormats/ReadingCover.heic>) |
| TIFF | `.tiff`, `.tif` | [ReadingCover.tiff](<../ImageFormats/ReadingCover.tiff>) |
| BMP | `.bmp` | [ReadingCover.bmp](<../ImageFormats/ReadingCover.bmp>) |
| WebP | `.webp` | [ReadingCover.webp](<../ImageFormats/ReadingCover.webp>) |
| ICNS | `.icns` | [AppIcon.icns](<../ImageFormats/AppIcon.icns>) |

### Code

| Format / Language | Extensions | Example |
| --- | --- | --- |
| Dockerfile | `.dockerfile` | [Dockerfile](<../CodeAndConfig/Dockerfile>) |
| Swift | `.swift` | [Sample.swift](<../Sample.swift>) |
| Python | `.py` | [ReadingList.py](<../CodeAndConfig/ReadingList.py>) |
| JavaScript | `.js`, `.mjs`, `.cjs` | [ReadingList.js](<../CodeAndConfig/ReadingList.js>) |
| JSX | `.jsx` | [ReadingCard.jsx](<../CodeAndConfig/ReadingCard.jsx>) |
| TypeScript | `.ts`, `.mts`, `.cts` | [ReadingList.ts](<../CodeAndConfig/ReadingList.ts>) |
| TSX | `.tsx` | [ReadingCard.tsx](<../CodeAndConfig/ReadingCard.tsx>) |
| Rust | `.rs` | [ReadingList.rs](<../CodeAndConfig/ReadingList.rs>) |
| Go | `.go` | [ReadingList.go](<../CodeAndConfig/ReadingList.go>) |
| Ruby | `.rb` | [ReadingList.rb](<../CodeAndConfig/ReadingList.rb>) |
| C | `.c`, `.h` | [ReadingList.c](<../CodeAndConfig/ReadingList.c>) |
| C++ | `.cpp`, `.hpp`, `.cc`, `.cxx`, `.hh`, `.hxx` | [ReadingList.cpp](<../CodeAndConfig/ReadingList.cpp>) |
| C# | `.cs` | [ReadingList.cs](<../CodeAndConfig/ReadingList.cs>) |
| Objective-C | `.m`, `.mm` | [ReadingList.m](<../CodeAndConfig/ReadingList.m>) |
| Java | `.java` | [ReadingList.java](<../CodeAndConfig/ReadingList.java>) |
| Kotlin | `.kt`, `.kts` | [ReadingList.kt](<../CodeAndConfig/ReadingList.kt>) |
| Shell | `.sh`, `.bash`, `.zsh`, `.bashrc`, `.zshrc` | [ReadingList.sh](<../CodeAndConfig/ReadingList.sh>) |
| Fish | `.fish` | [ReadingList.fish](<../CodeAndConfig/ReadingList.fish>) |
| PHP | `.php` | [ReadingList.php](<../CodeAndConfig/ReadingList.php>) |
| Lua | `.lua` | [ReadingList.lua](<../CodeAndConfig/ReadingList.lua>) |
| Perl | `.pl` | [ReadingList.pl](<../CodeAndConfig/ReadingList.pl>) |
| R | `.r` | [ReadingProgress.r](<../CodeAndConfig/ReadingProgress.r>) |
| SQL | `.sql` | [ReadingList.sql](<../CodeAndConfig/ReadingList.sql>) |
| GraphQL | `.graphql`, `.gql` | [ReadingList.graphql](<../CodeAndConfig/ReadingList.graphql>) |
| Makefile | `.mk` | [Makefile](<../CodeAndConfig/Makefile>) |
| HTML | `.html`, `.htm`, `.xhtml` | [ReadingCard.html](<../CodeAndConfig/ReadingCard.html>) |
| CSS | `.css` | [ReadingCard.css](<../CodeAndConfig/ReadingCard.css>) |
| SCSS | `.scss` | [ReadingCard.scss](<../CodeAndConfig/ReadingCard.scss>) |
| Vue | `.vue` | [ReadingCard.vue](<ReadingCard.vue>) |
| Svelte | `.svelte` | [ReadingCard.svelte](<ReadingCard.svelte>) |
| Less | `.less` | [ReadingCard.less](<ReadingCard.less>) |
| Diff / Patch | `.diff`, `.patch` | [LayoutChanges.diff](<LayoutChanges.diff>) |

### Text and Configuration

| Format / Language | Extensions | Example |
| --- | --- | --- |
| .dockerignore | `.dockerignore` | [.dockerignore](<../CodeAndConfig/.dockerignore>) |
| YAML | `.yaml`, `.yml` | [ReadingSettings.yaml](<../CodeAndConfig/ReadingSettings.yaml>) |
| TOML | `.toml` | [ReadingSettings.toml](<../CodeAndConfig/ReadingSettings.toml>) |
| XML | `.xml` | [ReadingList.xml](<../CodeAndConfig/ReadingList.xml>) |
| Property List | `.plist` | [ReadingSettings.plist](<../CodeAndConfig/ReadingSettings.plist>) |
| INI | `.ini` | [ReadingSettings.ini](<../CodeAndConfig/ReadingSettings.ini>) |
| Properties | `.properties` | [ReadingSettings.properties](<../CodeAndConfig/ReadingSettings.properties>) |
| Conf / Config | `.conf`, `.config` | [ReaderService.conf](<../CodeAndConfig/ReaderService.conf>) |
| Environment | `.env` | [.env](<../CodeAndConfig/.env>) |
| Git Ignore | `.gitignore` | [.gitignore](<../CodeAndConfig/.gitignore>) |
| EditorConfig | `.editorconfig` | [.editorconfig](<../CodeAndConfig/.editorconfig>) |
| Xcode Configuration | `.xcconfig` | [ReadingSettings.xcconfig](<../CodeAndConfig/ReadingSettings.xcconfig>) |
| Lock File | `.lock` | [Cargo.lock](<../CodeAndConfig/Cargo.lock>) |
| Log | `.log` | [Reading.log](<../CodeAndConfig/Reading.log>) |
| Plain Text | `.txt` | [ReadingNotes.txt](<../CodeAndConfig/ReadingNotes.txt>) |
| Custom-extension text | Detected as text | [Workspace.luma-note](<Workspace.luma-note>) |
