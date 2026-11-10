# User Guide

[Project home](../README.md) · [简体中文](USAGE.zh-CN.md)

Choose **Open Sample Workspace** on the welcome screen or File menu. Luma creates an editable local copy for your current interface language. Subsequent openings add missing files and preserve your changes.

## Workspace and file management

- Add multiple folders or drag files and folders into the window. Hidden entries such as `.env`, `.gitignore` and `.git` are visible and included in filename searches.
- Right-click a workspace folder to create a file or folder. New files open in Source. Names are validated and existing entries are never overwritten.
- Right-click files or folders to rename or Move to Trash. Folder operations include their contents. Unsaved documents prompt for Save / Don't Save / Cancel first. Failed operations preserve tabs and drafts; Trash failures do not fall back to permanent deletion.
- Drag one file or folder onto another workspace folder to move it. The destination highlights blue. Same-name overwrites, moves into a folder's own descendants and moves to the current parent are rejected.
- Renaming and moving update open tabs, save paths, folder expansion, bookmarks and reading records. Drafts and undo history remain intact.
- Directories load at startup. Activating Luma from another app refreshes roots, expanded / cached directories and filename search, at most once per 30 seconds. It does not reload your editing buffer.
- `⌘R` immediately refreshes directories and the current file, even with no file open. Unsaved files use the normal save / discard / cancel flow.
- The top tab strip scrolls horizontally. The toolbar provides refresh, Preview / Source, Find and Save. File information, save status and Reveal in Finder are available beside the reading area. The system sidebar button shows or hides the library.
- Open files through Finder's Open With or command-line arguments. Right-click tabs to close the current, other, left, right or all tabs, or reveal a file in Finder. Batch closing is relative to the clicked tab; cancellation, save failure or fresh edits preserve the whole group.
- Filename search and recent folders are available in the library. Projects, expanded subfolders, tab order and selection restore on restart. Projects without a saved expansion record start collapsed.

## Markdown reading

- Preview headings, paragraphs, lists, quotes, separators, inline formatting, links and aligned GFM tables. Wide tables scroll horizontally.
- The heading rail follows H1–H6 sections. Hover for a heading and excerpt, click to jump, or right-click to open a hierarchical outline with folding. Heading links and in-document anchors are supported.
- `⌘F` with preview focused keeps you in Preview. Search highlights visible text, counts results and cycles through them. It supports phrases across inline formatting, Unicode and emoji, visible code, math text and diagram labels. Matching ignores case.
- Text is centered with a default maximum width of 840 pt and shrinks with the window. Settings (`⌘,`) can fill the reading area or set a 640–1600 pt maximum width.
- Choose system, serif or monospaced text, 12–28 pt size and 1.30–2.40 line spacing. Defaults are system, 15 pt and 1.85. Changes apply immediately and survive restart. Headings, tables and code scale with the text; code and math retain their own fonts.
- Use Bookmarks → Add Current Position or `⌘D` to bookmark a position. Navigate, remove or deduplicate bookmarks per document. Reading position restores after reopening or restarting.
- Mermaid flowcharts, sequence diagrams and other diagrams render offline. Errors retain the source, with controls to view and copy it.
- Fenced code supports common languages, including Swift, Rust, TypeScript, JavaScript, Python and JSON, with Copy Code. Unknown or unlabelled code stays plain text.
- Local images support relative paths, absolute paths within the workspace scope, Unicode, spaces and URL encoding. Bitmap images and self-contained SVG fit the reading width; failed loads show a path hint.
- Bundled KaTeX supports `$…$` and `\(…\)` inline math, and `$$…$$` and `\[…\]` display math. Code is excluded and invalid math retains its source.

## Code and other formats

Code opens in a highlighted preview with a language label and light / dark appearance. Source mode edits the original text; returning to Preview displays the unsaved draft. HTML and Markdown embedded in code remain text.

PDF uses PDFKit for native reading and Find. Images support Fit to Window, zoom and Original Size; GIF shows its first frame. SVG adds a transparency checkerboard, Natural Text Size and source editing. An invalid SVG keeps its source available.

Unknown extensions undergo type and content checks. Readable UTF-8 opens as plain text and preserves the name, extension, BOM and line-ending style when saved. Archives, Office files, fonts, databases and other binary formats are excluded. Unsupported encoding or size displays an explanation and an Open in Default App action.

JSON and GeoJSON use a formatted code preview with two-space indentation, line numbers, typed colors and soft wrapping. Key order, numeric literals and escapes remain unchanged. JSONC retains comments and trailing commas. JSONL / NDJSON display each record with its source line number; invalid records show their source without hiding valid ones. Blank lines are ignored. Above 10,000 records or about two million formatted characters, the preview falls back to the complete source.

Vue / Svelte highlight template, script and style sections, including embedded JavaScript, TypeScript, CSS, Less, SCSS and template expressions. Less and Diff / Patch have their own highlighting. Components, scripts and patches are displayed as files rather than executed.

## Read tables

CSV / TSV use the first row as headers. Click a header or **Column Actions** to sort, filter by contained text or select values. Filters across columns intersect. Panels show value counts, empty values and parseable numeric ranges; long value lists are searchable.

The toolbar shows visible / total records and active conditions. Sorting and filtering only change the view. Row numbers retain each record's starting source line, including multiline cells. Clear one condition or Reset all filters and sorting.

Drag header separators to resize columns. Fit to Window distributes widths across the reading area; many columns still scroll horizontally. Double-click a cell to read or copy all its text.

## Content size and expanded reading

The source editor soft-wraps without inserting newlines. Code previews retain long lines with horizontal scrolling.

Markdown tables offer Expand Table; double-click a cell or focus it and press Return for its full text. Mermaid offers Expand Diagram, zoom, Fit to Window and Natural Text Size. Esc or Close returns to the original reading position. Standalone SVG and bitmap images provide natural / original sizing and Fit to Window.

## Inspect a source value

In Source, select one color, timestamp, byte size or escaped string, then choose **Inspect Selected Value**. Plain text also supports it. The tool processes one short selection at a time.

You can change the interpretation. Colors support `#RGB`, `#RGBA`, `#RRGGBB` and `#RRGGBBAA`, with a system color panel. Timestamps support seconds / milliseconds and UTC / local time. Byte sizes distinguish KB / MB from KiB / MiB. Strings show decoded JSON escapes and can be edited.

Only **Replace Selection** updates the draft. It preserves quoting and supports undo; saving follows the current Auto Save setting. If the source or selection has changed since opening the panel, replacement is refused so you can select again. Inspection stays local and does not scan the whole file.

## Edit, save and recover

- Text source supports editing, system undo / redo, cut / copy / paste and Find. Preview and tab switches keep drafts, selection and undo history.
- Auto Save under Settings → Editing is off by default. When enabled, it saves modified open text files about one second after typing stops; disabling it cancels pending saves. It preserves undo and does not write uncommitted input-method text.
- External conflicts and write failures pause Auto Save for that file and preserve the draft. Use `⌘S` to resolve the problem and resume.
- `⌘S` saves to the original file. Tabs and document titles indicate unsaved changes. Closing a file or window, reloading or quitting prompts for Save / Don't Save / Cancel. Save failures retain edits.
- Markdown previews follow the draft. SVG, JSON and CSV reparse asynchronously; invalid formats show errors while source remains editable and saveable.
- Activating Luma or switching tabs checks external changes; saving compares disk contents again. External changes or deletion require cancel, reload or explicit overwrite.
- Unsaved drafts live in memory; crash recovery is not available. Source scroll positions, PDF pages and image zoom are session-only. Markdown preview positions and bookmarks survive restart.

## Language and appearance

English is the default. **Settings → Appearance → Language** switches between English and 简体中文 and saves your choice. App menus, toolbars, settings, notices and preview controls update immediately. Existing language choices are retained.

Switching does not rewrite filenames or documents, reset drafts, selections or undo, or create replacement tabs. Some macOS panels may update after restarting. Open Sample Workspace chooses the current language's independent sample collection.

Appearance offers System / Light / Dark and applies immediately to windows, source editors and previews. Editing font size is separate from preview typography: 10–28 pt, default 13 pt, saved across restarts.

## Shortcuts

| Action | Shortcut |
| --- | --- |
| Open files / add folder | `⌘O` / `⇧⌘O` |
| Save original file | `⌘S` |
| Undo / redo | `⌘Z` / `⇧⌘Z` |
| Find in focused reader | `⌘F` |
| Next / previous Markdown match | `⌘G` / `⇧⌘G`; Return / Shift-Return in Find |
| Close Markdown Find | Esc |
| Bookmark Markdown position | `⌘D` |
| Close tab | `⌘W` |
| Next / previous tab | `⌃Tab` / `⇧⌃Tab` |
| Refresh directories and current file | `⌘R` |
| Settings | `⌘,` |

## Samples and reading behavior

Samples install into `~/Library/Application Support/Luma/Samples-2026.11.3-en` or `Samples-2026.11.3-zh-Hans`. Both have 67 representative formats and 93 recognized extensions. Reopening adds missing files; it never overwrites edits. Older editions remain untouched.

English entry points are `Welcome.md`, `MarkdownPreview.md`, `ImagesAndMath.md`, `LongDocuments.md`, `FindInDocument.md`, `SourceEditing.md` and `FormatExamples/FormatGuide.md`. Chinese has equivalent translated files. Samples deliberately include an invalid diagram, missing image and unsupported equation to demonstrate error fallback.

Find updates after a short pause (about 150 ms), retains the phrase across Preview / Source switches and keeps the current match through appearance changes. It searches visible text literally, without OCR or joining phrases across paragraphs or table cells. Search rendered equations by their visible text; search LaTeX commands in Source. Up to 5,000 matches can be highlighted and navigated; `+` marks additional results, and overly long queries ask to be shortened. Highlights do not change selection or copied text.

Typography changes preserve Find and try to retain your paragraph. Reopening prefers the saved paragraph, then the section, then overall progress if content has disappeared. Renaming or moving through Luma migrates reading records; external moves are not automatically associated. Up to 500 bookmarks per Markdown document are stored locally, outside the source file.

## Special filenames

Dockerfile supports `Dockerfile`, `Dockerfile.*` and `*.dockerfile` case-insensitively. Makefile supports `Makefile`, `GNUmakefile`, `Makefile.*` and `*.mk`. `.dockerignore` and `*.dockerignore` highlight comments, wildcards and negations. Source editing preserves tabs and rule text.

`.gitignore` and `*.gitignore` highlight comments, wildcards, negation and escapes. `.env`, `.env.local`, `.env.production`, `.env.example` and `*.env` support keys, values, quotes, multiline values, comments and variable references. Each language's CodeAndConfig / 代码与配置 folder has one example of each.

See the [Development Guide](DEVELOPMENT.md#reading-and-rendering-limits) for format and size limits.
