# Changelog

Versions follow semver; the version lives in `VERSION`.

## 0.2.0 (2026-10-30)

- `dd` removes a step: its capture goes to the Trash and its sidecar entry and memo block leave the case; `cmd-z` puts all three back. Also Step > Remove Step.
- Export writes the captions too: `notated/<case-id>.md`, the memo an evidence script drafts with the notated images, and `notated/<case-id>.yaml` for scripts; `export_labels off|md|yaml|both`, both by default.
- Fixed: the Typst fragment no longer lists a step whose capture cannot be decoded.
- sNotate > Settings… (`cmd-,`): General with snap, Import Config (old files kept as `.bak`), Export Config and the problems in the files; Presets with the nine slots, name, colour and sizes, a live preview, and import or export of one preset as `.snotatepreset`. Presets have names, shown in the Preset menu. Open Config Folder loses `cmd-,`.
- The config zip is made and read by scommon's `ConfigArchive`, shared with sView; nothing changes in the zip.
- `typst_import` replaces `typst_template_version`: by default the Typst fragment defines `shot` as a plain figure and compiles in any Typst document; `typst_import @namespace/name:X.Y.Z` imports `shot` from a template package instead. A config that still sets `typst_template_version` reports it as an unknown option.
- Published as `uSuite/snotate`: the bundle id is now `io.github.usuite.snotate`, so window positions and Open Recent start fresh; config in `~/.config/snotate/` is unchanged. A clone builds on its own, taking scommon 0.3.0 from GitHub.

## 0.1.0 (2026-10-27)

The first release: annotate a PoC case folder as one story and export it.

- Case documents: a case folder with its captures, memo and sidecar; new captures appear as steps in place, missing ones are said and kept in the sidecar, outside edits reload, saves happen on their own.
- Annotations: arrow, rectangle, ellipse, counter, text, highlight and spotlight, blur and pixelate, crop; selection, handles, nudging, duplication, z-order, undo and redo; style presets from `styles`; snapping.
- Counters numbered across the whole case with restarts; stamping crops and regions across steps; excluding steps.
- Storyboard with memo captions edited in place, reorder by drag, insert by drop or paste, and the rename plan.
- Export of PNG or JPEG per step with scale and burned-in captions, contact sheets as PNG or PDF, a Typst fragment for Typst memos, from the window or headless, for a case or a whole PoC root.
- Zoom and pan, sibling cases with `]` and `[`, the `:` command line, plain-text config, keymap and styles with `:set` and `:export-config`.
- The `snotate` launcher, file types for images and folders, an app icon and an About box.
- Every command in the menu bar with its keys from the keymap, Open Recent, and `?` for the live keymap over the window.
- Hardening: hostile fixtures (8k captures, 100 steps, broken and deep-colour captures, read-only folders, an ejected disk), a performance pass with the capture drawn by the GPU, and the fix for a crash on activation after an exception in a task.
