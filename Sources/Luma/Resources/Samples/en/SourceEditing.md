# From reading to editing

Markdown, SVG, JSON, CSV / TSV and code support **Source** mode; plain text opens directly in the editor. Switching tabs or preview keeps your draft.

## Save manually

Rewrite this sentence and watch the unsaved indicator. Press **Command-S** to save. Manual saving is the default. Under **Settings → Editing**, enable Auto Save to write changes about one second after typing stops.

Use Command-Z to undo, Shift-Command-Z to redo, and the system cut, copy and paste commands. Undo history survives preview and tab switches.

## Preview your draft

Change this list, then switch to Preview:

- A document
- A dataset
- A code snippet

Try editing [Project.json](Project.json) or [ReadingList.csv](ReadingList.csv). Incomplete JSON or CSV displays a parsing error; the source remains editable and can still be saved.

## Inspect a source value

In [Project.json](Project.json), select a value from `inspectionExamples`:

| Selection | Interpretation | What to observe |
| --- | --- | --- |
| `"#3A609580"` | Color | Translucent blue; replacement preserves quotes |
| `1794268800` | Timestamp, seconds | 2026-11-10T00:00:00.000Z |
| `1794268800123` | Timestamp, milliseconds | 2026-11-10T00:00:00.123Z |
| `1572864` | Byte size | 1536 KiB / 1.5 MiB; choose the interpretation manually for a bare number |
| `"1.5 MiB"` | Byte size | Binary and decimal units differ |
| The full string value after `escapedText` | Escaped string | Decoded newlines, tabs and emoji |

Choose **Inspect Selected Value** in the source toolbar. You can change the interpretation, time unit and time zone. Only **Replace Selection** updates the draft. Adjust a color, replace it and try Command-Z. Saving follows your current Auto Save setting.

If the source or selection changes while the panel is open, replacement is rejected; select again. Inspection processes one selected value locally.

## Long lines keep their content

The source editor soft-wraps to the window without inserting line breaks. Code previews retain long lines and scroll horizontally. Drafts, selections and undo history survive mode switches.

## Closing and conflicts

Closing a tab or window, reloading a file or quitting with unsaved edits prompts you to save, discard or cancel. Cancel and failed saves preserve your draft.

If another editor changes the file, Luma detects it when activated or when switching tabs. Before saving it checks again: cancel, reload the disk version, or explicitly overwrite it. External deletion also requires a decision.

The [Format Guide](FormatExamples/FormatGuide.md) includes SVG source / image switching and editable text with a custom extension. Samples are local editable copies; reopening them preserves edits and adds missing files.
