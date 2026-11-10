# Changelog

[Project home](README.md) · [简体中文](CHANGELOG.zh-CN.md)

0.9.0 is the current development version. Entries 0.1–0.8 preserve development and validation milestones from the original README; no release dates were recorded. Historical test counts describe those revisions, not the current checkout. See the [Development Guide](docs/DEVELOPMENT.md#structure-and-tests) for current validation.

## 0.9.0 · In development (2026-11-10, build 16)

- English is the default for new installations. Switch between English and Simplified Chinese and retain the choice; app menus, messages and offline preview controls update without rewriting user files.
- English project documentation and contribution templates, with a Chinese README and translated guides.
- Sample collection 2026.11.3 provides independent complete English and Chinese workspaces, each with 67 representative formats. Localized filenames, guides, code comments, data and PDFs are included. Editable copies are separate by language and edition, preserving older copies and edits.
- Restore project and subfolder expansion states at startup.
- Filter and sort CSV / TSV columns, inspect numeric ranges and empty values, resize columns and expand full cells while retaining source line numbers.
- Inspect selected colors, timestamps, byte sizes and escaped strings; explicit replacement uses the draft and native undo flow.
- Expand Markdown tables and Mermaid diagrams; SVG and bitmap readers offer natural / original size.

## 0.8

All 81 automated tests passed: 13 file / parser / save, 8 workspace, 7 reading persistence, 12 editing, 1 window-close and 40 Markdown tests, including parameterized formats and window decisions. Validation covered real writes; BOM, line endings and permissions; same-time / same-size external replacement; recreation after deletion; read-only, invalid and oversized writes; invalid-format saving and preview recovery; native undo / redo; tab changes and save points; conflict cancel / reload / overwrite with further changes; edits during saves; and cancellation or failed saves preserving drafts. Native windows verified close delegates and callback forwarding. WebKit verified unsaved Markdown heading, math and table updates. Full app-process keyboard / dialog regression was not performed.

## 0.7

All 62 tests passed: 8 file / parser, 8 workspace, 7 persistence and 39 Markdown tests. Covered typography defaults, persistence and invalid-value recovery. Real WebKit checked three fonts, scaled body / tables / headings, separate code / math fonts, last-setting-wins updates, paragraph restoration, search highlight positions and newly created views using saved typography. Full process restart and native Settings click regression were not performed.

## 0.6

All 58 tests passed: 8 file / parser, 8 workspace, 6 persistence and 36 Markdown tests. Covered width defaults and persistence, document / workspace recreation, bookmark save / deduplication / removal, corrupt metadata, missing files and final capture on close-before-quit. WebKit checked width changes preserving Find, paragraph restoration across width and content insertion, bookmark navigation and fallback when paragraphs disappear. Full process exit and native click regression were not performed.

## 0.5

All 48 tests passed: 8 file / parser, 8 workspace and 32 Markdown tests. WebKit checked phrases across inline styles; Unicode, emoji and special characters; overlay highlighting; cycling and distant navigation; no matches, clearing and fast-query cancellation; visible code, equations, SVG labels and expanded source; appearance / reload restoration; horizontal code results; and the 5,000-match limit. Find retained Preview, clickable links and the original DOM. Desktop screenshots and full native keyboard / click regression were not performed.

## 0.4

All 39 tests passed: 8 file / parser, 7 workspace and 24 Markdown tests. WebKit checked heading levels, Unicode / duplicate / punctuation anchors, navigation and heading focus, links, current-section tracking, appearance restoration, refresh cleanup and image / Mermaid layout changes. Also checked unique anchors for 2,005 duplicate headings, the 2,000-item outline limit, skipped levels and folding. Desktop screenshots and full native keyboard / click regression were not performed.

## 0.3

All 31 tests passed: 8 file / parser, 7 workspace and 16 Markdown tests. WebKit checked local images, mixed path encoding, SVG, four math delimiters, bundled fonts, exclusion of code / currency, error fallback and combined examples, plus tables, Mermaid and highlighting. Screen Recording permission was not requested.

## 0.2

All 22 tests passed: 8 file / parser, 6 workspace and 8 Markdown tests, including parameterized languages. New features were verified with real WebKit. Screen Recording permission, desktop screenshots and full click regression were not performed.

## 0.1

The user manually confirmed the window and examples displayed correctly.
