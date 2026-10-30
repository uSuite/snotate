# sNotate

<img src="brand/snotate-1024.png" alt="sNotate icon" width="128">

sNotate is a macOS-native image notation tool for PoC evidence folders: open a case folder of step screenshots, annotate them as one story with arrows, counters that continue across steps, text, highlights, blur and crop, and export one PNG per step into `notated/` while the originals stay untouched. Annotations live in a plain JSON sidecar beside the images and captions are the bullets of the case memo, so everything stays diffable in git. It is written in Swift with an AppKit canvas, uses only Apple frameworks and has no third-party dependencies

![A step with counters and an arrow](docs/images/canvas.png)

## Features

- One case per window: the folder `<case-id>/` with captures `<case-id>-<nn>.png`, the memo `<case-id>.md` and the sidecar `<case-id>.snotate.json`; the title says the case, the step and the file.
- Tools on single keys: arrow, rectangle, ellipse, counter, text with or without a pill and a leader, highlight and spotlight, blur and pixelate, crop; nine style presets from `~/.config/snotate/styles`; snapping to edges and centres.
- Counters number in story order across the whole case and can restart on any step; crops, blur and highlight regions stamp onto the following steps, the previous one or all.
- A storyboard of every step with its caption from the memo, edited in place; drag to reorder, drop or paste a capture to insert one, exclude a step, and a rename plan that numbers the files the way the evidence procedure does, applied only when you confirm it.
- Export: one PNG or JPEG per step at 0.5x, 1x or 2x, optionally with the caption burned in, a contact sheet as PNG or PDF, and a Typst fragment that includes every step in a Typst memo, and the captions as `<case-id>.md` in the evidence script's shape and `<case-id>.yaml`; a second export writes nothing that has not changed.
- Headless: `snotate --export <case or poc-root>` exports one case or every annotated case under a PoC root without opening a window.
- Never writes to the captures: annotations go to the sidecar (sorted keys, unknown keys kept), captions to one memo line at a time, output to `notated/`; `dd` moves a capture to the Trash, never deletes it. A failed save, a capture gone missing or a case folder that disappears is said in the window.
- Plain-text `config`, `keymap` and `styles` in `~/.config/snotate/`, applied the moment they change; `:set` changes one line, `:export-config` zips the folder.
- Fast: a 30-step case opens to the storyboard in under 200 ms, a drag frame takes 2 to 3 ms, and 30 annotated steps export in 0.6 s on an M-series Mac (bench/RESULTS.md).

![The storyboard with captions from the memo](docs/images/storyboard.png)

## Part of sSuite

sSuite is a small family of macOS tools that turn work done on screen into step-by-step evidence and guides, one job per tool, published under the [uSuite](https://github.com/uSuite) organization. The organization page explains why the family exists.

| Tool | Job |
| --- | --- |
| [sCapture](https://github.com/uSuite/scapture) | captures a window at a fixed size and scale into the active case folder (shell proof of concept today, Swift app next) |
| [sView](https://github.com/uSuite/sview) | views images and walks case folders from the keyboard |
| **sNotate** (this one) | annotates a case folder as one story and exports one image per step |
| sWalk | planned: renders a notated case as an animated step-by-step clip |
| [scommon](https://github.com/uSuite/scommon) | the Swift package the tools share: folders, sorting, config and keymap |

sNotate is the editing link: it opens the case folders sCapture fills and shows new captures as steps the moment they land, and its `notated/` export is what you flip through in sView, paste into a report, and what sWalk will animate. It reads the same case memo sView shows.

## Keys

Press `?` in a window for your live keymap, and every command is in the menu bar with its keys; the full built-in list is in [docs/keys.md](docs/keys.md). The most used ones:

| Keys | Action |
| --- | --- |
| `j` `k` | next, previous step |
| `gg` `G` | first, last step |
| `]` `[` | next, previous case folder |
| `cmd-1` `cmd-2` | step view, storyboard |
| `v` `a` `r` `e` `n` `t` `h` `b` `c` | select, arrow, rectangle, ellipse, counter, text, highlight, blur, crop |
| `1` to `9` | style preset |
| `gt` `lt` | stamp onto the following steps, the previous step |
| `x` | exclude the step |
| `dd` | remove the step: capture to the Trash, memo block out (`cmd-z` puts it back) |
| `=` `0` `+` `-` `z` | fit, actual size, zoom in, out, to an area |
| `cmd-e` `cmd-E` `cmd-C` | export the case, the step, copy the step as exported |
| `:` | command line: a step number, or any command |
| `cmd-z` `cmd-Z` | undo, redo |
| `cmd-,` | Settings: snap, config import and export, presets with a preview |
| `?` | the keys |

## Install

Requires macOS 26 or newer, on Apple silicon or Intel. Download `sNotate-<version>.zip` from the [latest release](https://github.com/uSuite/snotate/releases/latest), open it, and move `sNotate.app` to Applications. For the `snotate` command, link the launcher inside the app: `mkdir -p ~/.local/bin && ln -sf /Applications/sNotate.app/Contents/Resources/snotate ~/.local/bin/snotate`.

### The first open: sNotate Not Opened

The release is signed ad hoc, not with a paid Apple Developer ID, so Apple has not notarised it. The first time you open a downloaded copy, macOS stops it with "Apple could not verify sNotate is free of malware" (the dialog quotes the app name). Choose Done, then allow it once, either way:

- System Settings > Privacy & Security, scroll down to Security, and next to the line saying sNotate was blocked to protect your Mac, choose Open Anyway, confirm with your password or Touch ID, then Open. The button shows for about an hour after the blocked attempt.
- Or in Terminal, remove the download flag macOS checks: `xattr -dr com.apple.quarantine /Applications/sNotate.app`

From then on that copy opens like any app; each new version you download asks once more. Control-click > Open no longer skips the check on recent macOS. Only downloaded copies are checked: a copy you build yourself never carries the download flag, so it opens at once. If you would rather not run a binary you did not build, build it from source as below.

### Build from source

With Xcode 26 or newer and XcodeGen (`brew install xcodegen`): `make app` writes `build/sNotate.app`, and `make install` links the `snotate` command into `~/.local/bin`. SwiftPM fetches scommon from GitHub on the first build, or uses a `../scommon` checkout beside this one.

`snotate <case-folder or capture>...` opens cases, `ls -d poc-*/ | snotate -` reads them from stdin, and `snotate --export <case or poc-root>` exports without a window.

## Development

macOS 26 and Xcode 26 (Swift 6.2). `make test` runs the core tests, `make app` builds the app, `make smoke` drives it through scripted runs with snapshots in `build/smoke/`, `make hostile` opens hostile fixtures, `make bench` and `make idle` check the performance targets, `make golden` regenerates the rendering goldens, `make cheatsheet` writes docs/keys.md, and `make release` builds a universal app and zip. The design lives in [docs/02-tech-stack.md](docs/02-tech-stack.md), the decisions in [docs/DECISIONS.md](docs/DECISIONS.md) and the work items in [docs/01-backlog.md](docs/01-backlog.md).

## Licence

MIT, see [LICENSE](LICENSE).
