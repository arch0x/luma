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
