# sNotate: backlog

One thing, done well: open a PoC case folder, annotate its step screenshots as one story, export one PNG per step. Everything else is parked until that is boring.

The input is fixed by the evidence procedure: a folder named `<case-id>` holding `scap-*.png` or already renamed `<case-id>-<nn>.png` captures and, after the rename script, a memo `<case-id>.md` with a `- description` bullet before each `![](<case-id>-<nn>.png)`.

Priorities: P0 is the first usable release, P1 completes the story workflow, P2 is comfort, P3 is parked. IDs are stable (SN-xxx).

## Non-goals

- Not a general screenshot editor: no backgrounds, gradients, padding, device frames, GIF, recording, upload.
- Not an image editor: no colour correction, filters, resize beyond crop and export scale.
- No cloud, no accounts, no collaboration; the folder and git are the collaboration.
- No Windows, Linux, iPad.
- No capture at all: that is sCapture's job (the sibling `scapture` repository), decided 2026-10-25.

## E1 Case document (P0)

- SN-101 Open a case folder (Finder, drag and drop, `snotate <folder>`, or a file inside it) and show its images in evidence order: `<case-id>-<nn>` numeric order when renamed, otherwise capture-name order (chronological for `scap-*`). Non-image files are ignored, the memo is detected.
- SN-102 Annotations live in one sidecar per case, `<case-id>.snotate.json`, beside the images: pretty-printed, sorted keys, image-pixel coordinates with the step's pixel size recorded, one entry per step keyed by file name, so a rename by the evidence script (`--dry-run` first) can be followed and a diff shows the one arrow that moved. Because captures of a PoC share one window geometry, coordinates transfer between steps and survive a re-shot step; when a step's pixel size is an exact multiple of the recorded one (1x versus 2x capture) the annotations are scaled, otherwise the step is flagged. Originals are never written.
- SN-103 Autosave the sidecar on every change (debounced), reload it when it changes on disk (another editor, git checkout). No "unsaved changes" dialog exists.
- SN-104 Missing images referenced by the sidecar are listed, not fatal; new images in the folder appear as un-annotated steps at the right position.
- SN-105 Undo and redo across the whole case (not per image), unlimited within the session.

## E2 Annotation tools (P0)

Each tool is one key, Shottr style; a second press cycles the variant. Every drawn object is selectable, movable, resizable and editable later because nothing is flattened until export.

- SN-201 Arrow (`a`): straight, with optional curve handle; head size follows stroke width.
- SN-202 Rectangle (`r`) and ellipse (`e`): stroke only, with optional soft fill; corner radius from the style. A second `r` or `e` switches the fill for the next shapes, and `f` switches it on the selected ones (added 2026-10-27).
- SN-203 Numbered step counter (`n`): a filled circle with a number; the sequence continues across steps of the case (image 00 gets 1 and 2, image 01 continues at 3), renumbers automatically when one is inserted or deleted, and can be restarted per image with a toggle (`N`, added 2026-10-27).
- SN-204 Text (`t`): label with the style's font, optional background pill, optional leader line to a point; Vietnamese text renders correctly (system fonts, no custom font embedding needed). A drag draws the leader from the press point; a second `t` or `f` switches the pill; double-click or enter edits in place (added 2026-10-27).
- SN-205 Highlight (`h`): translucent marker rectangle, and spotlight variant that dims everything outside the rectangle. A second `h` or `f` switches marker and spotlight; several spotlights on a step share one dimming with a hole each (added 2026-10-27).
- SN-206 Blur and pixelate (`b`): rectangle region, radius from the style, meant for IPs, passwords, hostnames, licence keys in console screenshots. A second `b` or `f` switches blur and pixelate; strength grows with the region so large text is unreadable (added 2026-10-27). P2: a solid redact variant for real secrets, since blur and pixelation of known fonts can sometimes be partly reversed.
- SN-207 Crop (`c`): per-image crop rectangle stored in the sidecar; export writes the cropped result, the original stays whole. Aspect lock and "same as previous step" shortcut. Shift is the aspect lock, `C` is same as previous step, delete removes the crop while cropping (added 2026-10-27).
- SN-208 Selection (`v` or `Esc`): click, shift-click, marquee; arrow keys nudge by 1 px, shift-arrows by 10; `cmd-d` duplicate, `delete` remove, `cmd-[` `cmd-]` z-order (moved off the bare brackets 2026-10-27).
- SN-209 Snapping to image edges, to other objects and to a configurable grid; `cmd-;` toggles; coordinates and size shown while dragging, in image pixels.
- SN-210 Style presets from `~/.config/snotate/styles`: colour, stroke width, font size, blur radius, counter size; `1` to `9` switch presets; the default preset uses the report palette so every image in a report matches the decks and docs. Done 2026-10-27: blocks of `preset N` with `color`, `stroke`, `font`, `counter` (diameter), `blur`; undefined preset keys are refused; styles are the machine's, not the case's.

## E3 Storyboard (P1)

- SN-301 Storyboard view (`cmd-1` single step, `cmd-2` storyboard): all steps of the case as frames in reading order, each with its step number, file name and caption; zoom from thumbnails to readable; `j`/`k` or arrows move the selection, `Enter` opens a step in the single view, `Esc` comes back. Done 2026-10-27, with `i` for the caption and `+`/`-` for the frame size.
- SN-302 Captions are the memo: the `- description` bullet preceding `![](<file>)` in `<case-id>.md` is shown under its frame and edited in place; saving writes only that bullet back, keeping the rest of the memo byte-identical. When no memo exists, captions stay in the sidecar until the evidence script creates one, then migrate. Done 2026-10-27, with undo and guarded immediate writes.
- SN-303 Reorder steps by drag in the storyboard: the sidecar order changes and a "rename plan" is shown (`scap-...` to `<case-id>-<nn>`), applied only on explicit confirm, never silently, because the memo references the names. Done 2026-10-27: `J`/`K` and drag, `:rename-plan` in a sheet, following the evidence procedure.
- SN-304 Insert a step: drop a PNG onto the storyboard between two frames (from Finder, from sView via drag, from the clipboard); it is copied into the case folder with a provisional name and enters the rename plan. Done 2026-10-27: drop and `cmd-v` in the storyboard, `snotate-<time>` names.
- SN-305 Hide a step: mark a capture as excluded (wrong screenshot) without deleting; excluded steps are skipped by export and listed for the author to delete before the rename script runs. Done 2026-10-27: `x` toggles, `:excluded` copies the names, headless export lists them.
- SN-306 Apply across steps: a crop, a blur region or a highlight can be stamped onto the following steps, the previous step, or all steps (same browser chrome, same IP field on every console page). Stamped copies stay independent objects afterwards. Done 2026-10-27: `>` following, `<` previous, `:stamp-next`, `:stamp-all`; blur and highlight regions and the crop only.
- SN-309 Remove a step (`dd`, as in sView): the capture goes to the Trash, never deleted outright, and its sidecar entry and memo block leave with it; `cmd-z` puts all three back, and a memo edited since is never overwritten. Done 2026-10-29.
- SN-307 Link annotations (P2): an arrow from a counter in step N to the frame of step N+1 in the storyboard (Figma prototype style), drawn only in the storyboard export, never in the single PNGs.
- SN-308 Change spotlight (P2): consecutive steps share one geometry, so a pixel diff between step N-1 and step N yields the region that changed (the menu that opened, the dialog that appeared, the row that turned green); `D` proposes a highlight or spotlight rectangle around that region, which the author accepts, nudges or discards. Plain pixel compare on the decoded images, no model, under 50 ms per pair.

## E4 Export (P0/P1)

- SN-401 (P0) Export the case (`cmd-e`): renders every non-excluded step at native pixel size to `<case-folder>/notated/<same-file-name>.png` (decided, see `DECISIONS.md`), deterministic (same input, same bytes) so git does not churn. Stale files in `notated/` whose step was excluded or removed are deleted on export, nothing else there is touched. In the window since 2026-10-27.
- SN-402 (P0) Export one step (`cmd-shift-e`) and copy the rendered step to the clipboard (`cmd-shift-c`) for pasting into a chat or a deck. In the window since 2026-10-27.
- SN-403 (P1) Export options in the config, not a dialog: scale (1x or 2x), format (PNG default, JPEG quality), include or exclude step counters, include or exclude captions burned under the image. Done 2026-10-27: `export_scale`, `export_format`, `jpeg_quality`, `export_counters`, `export_captions`.
- SN-404 (P1) Storyboard export: one PNG or PDF contact sheet of the case with captions, and a Typst fragment (`<case-id>.typ`, one `#image` with its caption per step) for a memo-to-Typst path. Done 2026-10-27: `export_sheet`, `export_typst`, both in `notated/`; the fragment brings `#shot` itself and compiles in a Typst memo; 2026-10-30 `typst_import` names the package it comes from.
- SN-407 (P1) Labels with the export: the exported steps' captions as `notated/<case-id>.md` in the shape an evidence script drafts and as `notated/<case-id>.yaml`. Done 2026-10-29: `export_labels`, both by default.
- SN-405 (P2) Export for the whole PoC root (`snotate --export poc-demo`): headless, every case folder with a sidecar, for CI or a Makefile. Done 2026-10-27, also as `make export ROOT=<path>`.
- SN-406 (P3, parked) Animated walkthrough export, the manim idea: a case is a scene list, one scene per step; inside a scene the annotations animate in sidecar order (a counter pops, an arrow draws itself, a blur fades in) while the camera eases to the region they sit on, the caption shows as a subtitle, and the cut to the next step is a crossfade, which only works because every step has the same geometry so the UI change is the only motion. Rendered by the same `Renderer` with time as a parameter (the still export is the last frame), written with `AVAssetWriter` to MP4 at the case's pixel size, GIF optional. Turns a notated case into a training clip without a screen recording. Decided as a planned output (DECISIONS 2026-10-26): either a `:walk` export here or a sibling `sWalk` that takes the case folder, sidecar and memo as input and writes video files; the placement is chosen after `notated/` export has produced a real report. Timing and camera hints, when they come, live in the sidecar under their own keys. Downstream the clips sit beside the Typst documents, keyed by case id.

## E5 Navigation and keys (P0)

- SN-501 Steps: `j`/`k` next/previous step, `gg`/`G` first/last, `:N` go to step; `]`/`[` next/previous sibling case folder, same as sView. Digits are presets (SN-210), so the default keymap has no count prefixes; `space` is hold-to-pan (SN-502), not next step (2026-10-27). Done 2026-10-27 as `case-next`/`case-previous` and the `:` command line (a number or any keymap command); `:` has no completion yet.
- SN-502 View: `=` fit, `0` actual size, `+`/`-` zoom (`cmd-=`, `cmd--`, `cmd-0` in the View menu), `z` + drag zoom to area, trackpad pinch and scroll; arrow keys pan when nothing is selected and the image overflows (with a selection they nudge), `shift-` arrows pan further. Hold `space` to pan with the mouse while a tool is active; a tap does nothing. Done 2026-10-27, `cmd-9` fits and a percentage toast shows the zoom.
- SN-503 Tools by single keys as listed in E2, modifiers for variants (shift constrains, option draws from centre), `Esc` back to selection; `?` shows the live keymap. `?` done 2026-10-27: the live keymap over the window, in the cheat sheet's sections.
- SN-504 Keymap and config as plain text in `~/.config/snotate/keymap` and `config`, same grammar and parser as sView; `styles` for presets; the directory is exportable as a zip for transfer or archive. Done 2026-10-27 for `keymap` and `config` (`notated_dir`, `snap`), with `:set` and `:export-config`; `styles` done with SN-210 the same day.
- SN-505 Menu bar lists every command with its key; Open Recent lists case folders. Done 2026-10-27: menus from `MenuLayout` with the keymap's keys, rebuilt when it changes, Open Recent from macOS's recent documents.
- SN-506 Settings window (`cmd-,`), the macOS Settings look: General (snap, Import Config, Export Config, the problems in the files) and Presets, Terminal's profile layout with the nine slots, a name, colour and sizes per preset, a live preview, add, duplicate, remove or revert, and one preset imported or exported as `.snotatepreset`. The window writes the same text files. Done 2026-10-30.

## E6 App shell and quality (P0/P1)

- SN-601 (P0) Native window, one case per window, title `<case-id>  step i/N  file`; `cmd-n` opens another case.
- SN-602 (P0) Register the folder-open and image UTIs; `snotate` CLI launcher installed by `make install`. Done 2026-10-27: images at rank Alternate and folders at rank None (registered since Phase 0, now checked by smoke), `scripts/snotate` in the bundle and linked by `make install`.
- SN-603 (P0) Rendering is one code path for screen and export (Core Graphics into a CGContext), so what is on screen is what is in the PNG; golden-image tests guard it.
- SN-604 (P1) Signed and notarised build, zip on GitHub Releases, Homebrew cask in the `uSuite/homebrew-tap` tap with sView. Tooling done 2026-10-27: icon, About box, `make release` (universal, ad hoc without a Developer ID), `make notarize`, `make cask`, README, CHANGELOG and docs/keys.md; signing, publishing and the tap need a Developer ID and a git remote.
- SN-605 (P1) Hostile fixtures: 8k x 8k screenshot, 100 steps, sidecar with unknown keys (ignored and preserved), memo with CRLF, image renamed while open, folder on an external disk ejected. Done 2026-10-27 as `make hostile`, with a BOM memo, broken and deep-colour captures, NFD names, a conflicted sidecar, a deleted capture and folder and a read-only folder added.
- SN-606 (P1) Performance: open a 30-step case in under 500 ms to the storyboard, tool response under one frame at 120 Hz, export of 30 steps under 5 s on Apple Silicon. Done 2026-10-27 as `make bench` and `make idle` (results in bench/RESULTS.md): 182 ms to the storyboard, 0.57 s for 30 annotated steps, drag frames 2 to 3 ms median; the worst frame after a gesture's first is 6 to 7 ms at 8k and 8.4 to 9.5 ms at 1600x1000 on a loaded machine.

## E7 Capture (withdrawn)

Moved to sCapture on 2026-10-25 (sCapture's `docs/01-backlog.md`, SC-xxx). The only touch point left here is SN-701: when sCapture writes a new file into the open case folder, sNotate picks it up through the folder watch (SN-104) and, if `follow_capture true` is set, selects it.

## Parked (P3)

- OCR of a region to clipboard (Vision) for copying console output into the memo.
- Text-only blur (detect text with Vision, pixelate just the glyphs).
- Side-by-side diff of two steps with synced zoom (shared with sView SV-604).
- Per-case style override file for a customer whose brand colours must appear in the report.
- Memo bullets beyond one line (sub-bullets) edited in the storyboard; v1 edits the first line only.
- Fixtures as scenes: `scripts/make-fixtures.swift` already draws a console page from code; if sNotate ever needs many synthetic cases (docs, tests, demos without customer data), grow it into a small scene description (`page`, `panel`, `button`, `dialog`) rather than hand-drawing each case, in the manim spirit of describing a picture and rendering it deterministically.
