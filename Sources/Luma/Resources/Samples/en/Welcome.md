# Read your files with clarity.

Welcome to **Luma**, your local reading space.

This is the **2026.11.3 English sample collection** for Luma 0.9.0, with 67 representative formats and languages. Equivalent file extensions share one example.

Open a design document, an experiment or a new piece of code in the same window. Your files stay where they are.

## Start with a folder

- Use the folder button at the top left to add a project.
- Select a file in the sidebar; opened files remain in tabs.
- Drag files or folders into the window to open them.

> Source mode lets you edit text files. Press Command-S to save, or enable Auto Save in Settings.

## Try three reading tools

1. Open [ReadingList.csv](ReadingList.csv), click **Status** and select only **To read**. Try numeric sorting and empty-value filtering in **Pages**. Double-click a long note to read it fully; **Reset** restores all records.
2. Open [Project.json](Project.json), switch to **Source** and select a value in `inspectionExamples`. Choose **Inspect Selected Value** to inspect a color, timestamp, byte size or escaped string. Adjust colors with the system panel, or change timestamp units and time zones. Only **Replace Selection** changes the draft; you can undo it.
3. Open [Markdown Preview](MarkdownPreview.md) and expand a table or diagram. Read diagram labels at natural text size, then press Esc to return to your place.

## Read the same content in different ways

Switch Markdown between formatted preview and source. Tables, Mermaid diagrams and highlighted code work offline. JSON has a formatted code preview; CSV has a table view.

- [Markdown Preview](MarkdownPreview.md): tables, flowcharts, sequence diagrams and code.
- [Images and Math](ImagesAndMath.md): local PNG / SVG images and inline / display equations.
- [Long Documents](LongDocuments.md): heading navigation, folding, bookmarks and reading position.
- [Find in Document](FindInDocument.md): Command-F, visible-text highlighting and previous / next matches.
- [Source Editing](SourceEditing.md): edit Markdown, JSON, CSV and code, preview a draft and save it.
- [Complete Format Guide](FormatExamples/FormatGuide.md): real image encodings, document formats, code, configuration and custom-extension text.

Text is centered by default. Open Settings with Command-comma to set a maximum width or fill the reading area. Under **Markdown Reading**, choose a system, serif or monospaced font, a 12–28 pt size and 1.30–2.40 line spacing. Settings apply immediately and preserve your paragraph where possible; code and math keep their own fonts.

Hover over the heading rail to add a section bookmark, or press Command-D to bookmark your current position. Reopening a document or restarting Luma restores your reading position.

```swift
struct ReadingSpace {
    let name = "Luma"
    let staysLocal = true
}
```

## About these samples

The first opening creates a separate editable copy. Reopening adds missing files and preserves your edits. Older editions and their drafts stay intact.

The app opens the English or Chinese collection according to the current interface language. Change it in **Settings → Appearance → Language**, then choose **Open Sample Workspace** again to open the other collection. Existing tabs and files are unchanged.

## A little room to focus

1. Command-O opens files; Shift-Command-O adds a folder.
2. Command-F searches the current text or PDF.
3. Command-W closes a tab; Command-R refreshes directories and the current file.

---

**Supported files:** Markdown, PDF, SVG, common images, JSON, CSV, TSV, UTF-8 text and code. Unknown extensions can open as text when their contents are readable.

Read, make a note and keep your files local.
