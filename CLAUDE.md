# sNotate

macOS-native image notation tool for PoC evidence folders: open a case folder of step screenshots, annotate them as one story, export one PNG per step. Sibling of sView (../sview) and sCapture (../scapture), same stack and conventions; shared code lives in scommon. Swift 6.2, AppKit app and canvas with SwiftUI views, zero dependencies, macOS 26. Read docs/02-tech-stack.md (architecture, sidecar format), docs/01-backlog.md (SN-xxx items), docs/DECISIONS.md (source of truth), docs/local/STATUS.md (untracked, where we are), docs/local/03-plan-claude-code.md (untracked, phases).

## Commands

- `make gen`     regenerate sNotate.xcodeproj from project.yml
- `make test`    scommon's tests when `../scommon` is checked out, then swift test on SNotateCore
- `make golden`  regenerate golden PNGs in fixtures/golden/ (only when a rendering change is intended; look at every changed image before committing)
- `make app`     xcodebuild Debug sNotate.app into build/
- `make run`     build and launch on fixtures/poc-sample-vm-migrate/
- `make smoke`   scripted UI smoke test with screenshots in build/smoke/
- `make activate` activation after an exception (the Phase 5 crash), needs the desktop
- `make hostile` hostile fixtures in the UI (SN-605): 8k, 100 steps, broken captures, disk ejected; ends with make activate
- `make bench`   performance targets (SN-606), appends to bench/RESULTS.md; `make idle` idle CPU and leaks
- `make coverage` line coverage of SNotateCore
- `build/sNotate.app/Contents/MacOS/sNotate --export <case-folder or poc-root>...`  headless export into notated/
- `make export ROOT=<poc-root>`  headless export of every annotated case under ROOT
- `make install` links the `snotate` launcher into ~/.local/bin (`snotate <case or capture>`, `snotate -` from stdin, `snotate --export <path>`)

## Layers

Shared (the scommon package, the sibling ../scommon when present, else `uSuite/scommon` from GitHub; re-exported by SNotateCore) -> Core (Sources/SNotateCore: CaseDocument, Model, Geometry, Commands, Renderer, Memo, Exporter; Foundation, CoreGraphics, ImageIO, CoreText and CoreImage only, never AppKit or SwiftUI, fully tested) -> UI (Sources/sNotate: CanvasView, StoryboardView) -> App (menus, UTIs, launcher). One renderer for screen and export. Every user action is a Command.

## Rules

- Plan, get approval, then implement. PoC in scratch/ when unsure.
- One logical change per commit; the message says why. Default git identity, no trailers.
- make test before every commit; make app before UI commits. Never commit red.
- Never write to the original images. Sidecar and notated/ only; captures are renamed only by a rename plan the author confirms (SN-303), never rewritten; the memo is edited one bullet line at a time (an image with no bullet gets one inserted above it, and `dd` takes a removed step's block out, see DECISIONS). A capture leaves the folder only through `dd`, to the Trash.
- Sidecar JSON: sorted keys, two-space indent, pixel coordinates, unknown keys preserved.
- No third-party packages without a DECISIONS.md entry.
- Shared code changes in ../scommon first, test first, with a tag per change set (patch for a fix, minor for a new key or type); it is good once this app's smoke passes against it. Raise the `from:` minimum in Package.swift when this app needs a newer tag; never edit scommon's files through this checkout.
- Multi-line calls: one argument per line. No banner comment lines.
- Plain text, no em-dash character, no horizontal rules in markdown, one paragraph per line.
- git-flow: branch feature/<name> off develop, merge back with --no-ff; master only via release/X.Y.Z, tagged vX.Y.Z. Semver lives in VERSION.
- Update docs/local/STATUS.md at the end of every session.
