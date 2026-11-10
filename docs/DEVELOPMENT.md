# Development Guide

[Project home](../README.md) · [User Guide](USAGE.md) · [简体中文](DEVELOPMENT.zh-CN.md)

Run commands from the repository root. Requires macOS 14+, Swift 6.2+ and Apple Command Line Tools with a compatible Swift toolchain. There are no remote SwiftPM dependencies or npm build steps.

## Build and debug

```sh
swift run Luma
swift run Luma "Sources/Luma/Resources/Samples/en/Welcome.md"
```

Package an app for Finder, using debug by default or an explicit release configuration:

```sh
zsh scripts/build-app.sh
open dist/Luma.app
zsh scripts/build-app.sh release
```

The script generates icons, builds the executable, copies resources and applies local ad hoc signing. No Developer ID signing or Apple notarization is configured. Version and bundle identifiers live in `scripts/build-app.sh`; `.build/` and `dist/` are ignored.

## Structure and tests

- `Sources/ReaderCore`: file boundaries, format detection, CSV / JSON models, text storage and localization resources. `PlainTextFallback.swift` excludes binary formats; `SVGDocument.swift` validates SVG; `TextFileStore.swift` handles versions, encoding, line endings and coordinated saves.
- `Sources/Luma`: windows, workspace state, SwiftUI readers and AppKit / PDFKit / WebKit bridges. `SVGReader.swift` provides isolated vector preview and zoom.
- `MarkdownImages.swift`: scoped local image resolution, background reads and thumbnail cache. `MarkdownOutline.swift`: heading hierarchy and native outline. `MarkdownFind.swift` and bundled `search.js`: Find state, visible-text indexing and overlay highlighting.
- `MarkdownReading.swift`, `MarkdownBookmarks.swift` and bundled `reading.js`: paragraph anchors, reading positions, restoration and bookmarks. `MarkdownTypography.swift`: font and typography settings; Workspace persists preferences.
- `SourceEditor.swift`: one native text view and undo history per tab. `DocumentDialogs.swift` and `WorkspaceWindowBridge.swift`: unsaved changes, conflicts and window-close protection.
- `Sources/Luma/Resources/Samples/en` and `zh-Hans`: localized editable sample fixtures. `Samples/catalog.json` describes both collections.
- `Tests/ReaderCoreTests`: parser boundaries, invalid input, read limits and symbolic-link cycles.
- `Tests/LumaTests`: real file operations, tab reuse, source fallback, workspace restoration, search, native media and real WebKit previews. Test preferences are isolated from app configuration. Existing Chinese interaction fixtures explicitly choose Chinese; language tests exercise the English default and saved choices.

```sh
zsh scripts/test.sh --no-parallel
```

`ViewState.swift` and the test script accommodate macro-loading differences in some Command Line Tools installations. If a CI host cannot run nested build sandboxes, append `--disable-sandbox` to the test or packaging script. This affects SwiftPM building only; it does not grant the app extra access.

Native tests need window services, pasteboard access and permission to launch WebKit subprocesses. SwiftPM's `--disable-sandbox` cannot remove restrictions imposed by a host environment. Tests create their own preview views and do not read the desktop or require Screen Recording. Appearance fixtures supply the same presentation boundary as SwiftUI Window scenes. Historical validation in the [Changelog](../CHANGELOG.md) is not a statement about the current checkout.

## Continuous integration

The [workflow](../.github/workflows/ci.yml) runs on pushes, pull requests and manual dispatch, with read-only repository permissions. It is configured for macOS 15 and macOS 26 Apple Silicon runners, selecting Xcode 26.3 through `DEVELOPER_DIR`.

Each environment records system / toolchain details, checks generated localization and sample catalogs, runs ReaderCoreTests, runs LumaTests serially, builds a release app, verifies its ad hoc signature and creates a ZIP. Artifacts and logs are retained for seven days; available logs upload even after failures. No Developer ID, certificate or repository secret is required. Artifacts are not notarized.

The minimum deployment target remains macOS 14 in `Package.swift`; these runners do not replace testing on macOS 14 or Intel hardware. GitHub-side results will become available after the repository is configured and pushed.

## Interface localization

English is the default for new preferences and unsupported saved language values. A saved `en` or `zh-Hans` choice takes precedence over that default.

`Localization/en.json` maps stable Chinese message identifiers to English translations. These identifiers remain internal; project documentation and source comments use English. SwiftUI uses `tr` / `trKey`, and worker-side ReaderCore errors use `coreText`. Interpolations use numbered placeholders, keeping filenames and user content separate from templates.

```sh
python3 scripts/generate-localizations.py
python3 scripts/generate-localizations.py --check
```

The generator writes ReaderCore's `en.lproj` and `zh-Hans.lproj` resources and the offline preview's `localization.js`. CI checks that they are current. Preserve `{0}` and other placeholders. Do not translate user paths, document content, source code or format identifiers.

The language preference is local. Switching updates existing views and menus rather than rebuilding Workspace; previews capture a reading anchor before layout. macOS manages system-panel localization, which may update after restart.

## Native interaction

Tab context menus use AppKit for right-click and Control-click. Hit testing checks both the tab and its visible horizontal scroll area. Normal clicks, close buttons and scrolling retain their behavior. Tab closure and toolbar teardown remove event monitors.

## Reading and rendering limits

| Resource | Limit / behavior |
| --- | --- |
| UTF-8 text reads and saves | 4 MB |
| PDF | 128 MB |
| Standalone bitmap | 64 MB; thumbnail longest edge 4096 px |
| Standalone SVG preview | 1 MB; source editing remains available up to 4 MB |
| CSV / TSV preview | 10,000 rows, 200 columns |
| Code highlighting | Plain-text fallback above 100,000 characters |
| JSON formatting | Source fallback above about two million formatted characters; line numbers omitted above 20,000 lines |
| JSON Lines | Source fallback above 10,000 records or the formatting budget |
| Mermaid | 40 diagrams per document, 50,000 characters and 500 edges per diagram |
| Inline local images | 100 images per document; 64 MB cache; 2048 px thumbnails; bitmap source up to 64 MB, SVG up to 1 MB |
| Math | 500 expressions per document; 10,000 characters per expression |
| Outline | First 2,000 headings; later heading anchors remain usable |
| Filename search | Scan at most 25,000 entries; show 200 matches; include hidden entries and skip common build directories |
| Markdown Find / bookmarks | First 5,000 matches; 500 bookmarks per document |

PDF and bitmap readers do not edit their sources. GIF shows the first frame. Raw HTML in Markdown is shown as text. Workspace-wide content search, continuous file watching, App Sandbox security-scoped access and App Store distribution are not implemented.

By default, drafts stay in memory until `⌘S`. Optional Auto Save writes about one second after typing stops. There is no crash draft recovery. Saves use system file coordination and atomic replacement, preserving UTF-8 BOM and line endings (LF / CRLF / CR; mixed endings normalize to the first style). They do not autoformat JSON or rewrite CSV. Read, permission, size and write failures preserve the draft and cancel closing. External-change checks do not automatically replace the editor buffer.

Markdown uses embedded WebKit, Marked for GFM, highlight.js, Mermaid, KaTeX and DOMPurify. Versions, hashes and licenses live in `Sources/Luma/Resources/Markdown/vendor/manifest.json` and `THIRD_PARTY_NOTICES.txt`. Runtime engines and fonts load only from a bundled allowlist; network subresources are disabled. User-clicked links are delegated to the app. Diagrams use strict mode, retaining source on errors or budget exhaustion.

Images use a separate local protocol. Paths resolve relative to the Markdown file, within its most specific workspace root, or its own folder and descendants when no root contains it. For `../assets/…`, add a parent folder containing both the document and assets. Decoding, normalization and symlink resolution must stay in scope. Remote images do not load automatically. SVG is rendered as an isolated image with no scripts or external resources; DTD / entity declarations are rejected.

KaTeX supports a subset of LaTeX math, not full TeX documents. Invalid or oversized expressions preserve source. Macros are local to each expression, expansion is bounded, and trusted commands involving HTML or external resources are disabled. Amounts, escaped dollar signs and code stay unchanged.

The outline uses rendered headings, excluding code and raw HTML. Unicode, duplicate, blank and punctuation-only headings receive distinct stable anchors. Long outline labels are shortened. Heading positions update after images, math fonts and reader resizing; scrolling uses cached positions.

## Find and reading records

Find searches visible text literally, matching whitespace runs without regular expressions or OCR. It excludes toolbars, copy buttons, hidden MathML and collapsed source, and does not join phrases across paragraphs or cells. Use Source to find LaTeX commands. An additional-result `+` appears beyond 5,000 matches; excessive query lengths ask the user to shorten the query.

Text ranges and transparent overlays preserve links, syntax structure, selection and copying. Only nearby viewport matches are painted. Resizing, layout changes and horizontal code scrolling reposition highlights. Appearance changes and reloads rerun Find while retaining the current result.

Typography changes update page layout without reparsing documents or reloading images. Settings apply to all Markdown previews and use built-in macOS fonts. Reading positions combine paragraph signatures, within-paragraph progress, heading anchors and overall progress. Restoration waits for images, math fonts and diagrams, preferring the original paragraph, then section, then overall progress. Different window sizes still try to preserve the same content.

Records use normalized file paths. Luma moves and renames migrate them; external moves are not automatically associated. Reading positions and bookmarks live in app UserDefaults, outside document files. Scroll saves are coalesced; bookmark changes save immediately. Closing, switching to Source and normal quit capture the latest position, and quitting completes pending bookmark and save work. Startup restores tab order and selection, skipping missing files. Non-Markdown scroll, PDF page and zoom state remain session-only.

## Maintain sample resources

Edit localized text fixtures directly in `Sources/Luma/Resources/Samples/en` and `zh-Hans`. Add equivalent entries to `Samples/catalog.json` and update the guide introductions in `Samples/FormatGuide.en.md` and `Samples/FormatGuide.zh-Hans.md`. Generate and check both catalogs and guides:

```sh
python3 scripts/refresh-samples.py
python3 scripts/refresh-samples.py --check
```

This does not overwrite fixture bodies. `--text-only` remains a compatibility alias. Each catalog must cover every extension in `DocumentKind.extensionsByKind`, once, with a real representative file.

Regenerate native PNG / PDF and image encodings with Apple tools:

```sh
swift -module-cache-path "$PWD/.build/module-cache" scripts/generate-assets.swift "$PWD" --refresh-samples
```

Use `--refresh-pdf` to update only PDFs. Both languages share the visual geometry and brand palette, with localized text. Each has a real lossless WebP fixture; re-encoding WebP is an explicit maintenance step requiring Python with Pillow:

```sh
python3 scripts/refresh-samples.py --refresh-webp
```

Normal app builds use checked-in fixtures and require no Python imaging package. Editable installs use `~/Library/Application Support/Luma/Samples-2026.11.3-en` and `Samples-2026.11.3-zh-Hans`. Language and edition directories stay independent; older editions and user edits are retained. Bump `SampleWorkspace.edition`, fixture metadata, guide introductions and documentation together.

## Icons and visual resources

The [blue icon master](../Sources/Luma/Resources/Brand/AppIcon.png) remains unchanged. Packaging locates its opaque tile, takes a centered square crop at uniform scale and generates icon sizes plus `dist/AppIcon.icns`. This removes exterior padding while preserving the mark's proportions and transparent rounded corners. Both sample ICNS files update from the same export. The [design prompt](../design/AppIcon-prompt.txt) is checked in.

Native UI and Markdown share blue accents: `#3A6095` with paper `#FCFCFA` in light appearance; `#A6C5F2` with ink `#1A202B` in dark. Active tabs, links and focus use blue, while Find uses amber for matches and the current result.
