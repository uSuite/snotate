# sNotate: technology stack

Same foundation as sView, on purpose: Swift 6.2, SwiftUI shell, AppKit canvas, Apple frameworks only, macOS 26 Tahoe, no third-party packages, config in `~/.config/snotate/`. What differs is the core: sNotate is a document editor with a renderer, sView is a viewer with a cache. Status: proposed 2026-10-25, see `DECISIONS.md` for what is already fixed.

## Frameworks

| Need | Framework | Notes |
| --- | --- | --- |
| Decode | ImageIO | Full-size decode once per step (screenshots are a few MB); downsampled decode only for storyboard thumbnails. |
| Render | Core Graphics (`CGContext`) | One `Renderer.draw(step, into: context, scale:)` used by the on-screen `NSView` and by export. No second code path, no SwiftUI `Canvas` for the image. |
| Text | Core Text via `NSAttributedString` drawn into the CGContext | System font by default (SF Pro, with full Vietnamese coverage), style presets choose the family and size. |
| Blur, pixelate | Core Image (`CIGaussianBlur`, `CIPixellate`) applied to the cropped region, result drawn back with Core Graphics | Rendered once per region and cached until the region or image changes. |
| Export | ImageIO `CGImageDestination` PNG, metadata stripped, fixed compression | Deterministic bytes for a given input so git stays quiet. |
| Canvas and input | `NSView` (layer-backed) in `NSViewRepresentable`, first responder | Mouse, trackpad, keyboard, drag and drop all land in one place; hit-testing is in the core (pure geometry), not in the view. |
| Storyboard | SwiftUI `LazyVGrid` of thumbnails drawn by the same renderer at thumbnail scale | SwiftUI is good at this part. |
| Memo | Own line-based Markdown bullet locator | Finds the `- ` line preceding `![...](<file>)`, rewrites that line only; no Markdown parser. |
| Sidecar | `Codable` JSON with sorted keys and pretty print | Zero dependency, diffable, hand-fixable. |
| Watch | `DispatchSource` on the folder and the sidecar | Reload on external change, debounced. |
| Undo | Own command-pattern stack over the document (not `UndoManager`) | Case-wide, serialisable later if wanted; `UndoManager` is bridged only for the Edit menu. |
| Tests | Swift Testing on `SNotateCore`, golden PNGs for the renderer | Golden images compared with a per-pixel tolerance on the same machine class. |

## Architecture: core, UI, app

```
App     main.swift and AppDelegate (AppKit lifecycle, see decisions), menus, UTIs, launcher, config and keymap loading
UI      CanvasView (NSView), StoryboardView (SwiftUI), Inspector (SwiftUI, minimal), ToolOverlay
Core    SNotateCore library:
          CaseDocument      folder scan, step order, memo detection, sidecar load/save, watch
          Model             Step, Annotation (enum with associated geometry), Style, Preset
          Geometry          hit-testing, handles, snapping, pixel <-> view transforms
          Commands          every user action as a Command; Dispatcher applies to the document
          Renderer          draw(step) for screen and export; Counter numbering across steps
          Memo              bullet locate and rewrite
          Exporter          per step, per case, storyboard sheet, Typst fragment
          Config            snotate settings over the shared KeyValueSettings and ConfigPaths(app:)
Shared  SCommon target, copied whole from sView until the scommon package replaces it:
          folder scan, natural sort, poc- parsing, key value parser, keymap grammar, config paths, watchers
```

Data is the `CaseDocument` (steps, annotations, order, exclusions), logic is `Geometry`, `Renderer`, `Memo`, `Exporter`, control is the `Dispatcher`; the UI renders state and emits Commands. The core imports Foundation, CoreGraphics, ImageIO, CoreText (text measuring and drawing) and CoreImage (blur and pixelate) only, never AppKit or SwiftUI, so `swift test` runs it headless (DECISIONS 2026-10-26).

## Data model: the sidecar

`<case-id>.snotate.json` beside the images, one per case folder. Coordinates in image pixels of the original file, origin top-left, floats with at most two decimals, with the step's pixel size recorded so a 2x capture of the same window can reuse a 1x step's annotations by scaling. Keys sorted, two-space indent, trailing newline, so a diff is a diff.

```json
{
  "counter": "continue",
  "steps": [
    {
      "crop": [0, 88, 1920, 992],
      "excluded": false,
      "file": "poc-demo-vm-stop-00.png",
      "items": [
        {
          "at": [412, 230],
          "preset": 1,
          "type": "counter"
        },
        {
          "from": [600, 300],
          "preset": 1,
          "to": [412, 240],
          "type": "arrow"
        },
        {
          "preset": 1,
          "rect": [1500, 40, 240, 28],
          "type": "blur"
        },
        {
          "at": [620, 310],
          "preset": 2,
          "text": "Chọn VM cần dừng",
          "type": "text"
        }
      ],
      "size": [1518, 892]
    }
  ],
  "version": 1
}
```

Unknown keys are preserved on save so a newer sNotate does not strip what an older one wrote, and vice versa. The exact bytes (number arrays on one line, everything else expanded, two decimals) and the `assets/` relative paths are fixed in `DECISIONS.md` (2026-10-26); the item format, with counters numbered from story order rather than stored, is in `DECISIONS.md` too. The memo keeps the captions; the sidecar keeps a caption only while no memo exists.

## Configuration

`~/.config/snotate/` (decided 2026-10-25, same rules as sView: lower-case, no white space, exportable as a zip). Files: `config` (`key value` lines: `notated_dir notated`, `snap true`, `export_scale 1`, `export_format png`, `jpeg_quality 90`, `export_counters true`, `export_captions false`, `export_sheet off`, `export_typst false`, `typst_import none`, `export_labels both` now; `counter continue` and `grid 8` with their features), `keymap` (same grammar as sView), `styles` (presets, one per block, `preset 1`, `name Primary`, `color #00579C`, `stroke 4`, `font 28`, `counter 36`, `blur 12`; the font family is the system font), `state.json` (disposable).

## Build and repository layout

Mirror of the sview repo so Claude Code sessions feel identical: `Package.swift` (library `SNotateCore` with its tests and the local `../scommon` dependency, plus an `sNotate` executable so the Command Line Tools can build the app), `project.yml` for XcodeGen (no committed xcodeproj), `Sources/SNotateCore`, `Sources/sNotate`, `Tests/SNotateCoreTests`, `Resources/`, `fixtures/` (a small synthetic case folder plus golden PNGs), `scripts/`, `docs/`, `Makefile` with `gen build app run test golden smoke install clean`, `CLAUDE.md`. Xcode 26 or newer.

## Sharing code with sView

sView, sNotate and sCapture all need folder scanning, natural sort, `poc-` name parsing, the `key value` config parser, the keymap grammar and the `~/.config/<app>/` logic, perhaps 400 lines in total. With three siblings the rule of three is met, so these become the `scommon` SPM package in its own sibling repository, depended on by local path (`../scommon`). Timing: sView moved this code into its own `SCommon` target on 2026-10-26, and sNotate Phase 0 copies `Sources/SCommon` and `Tests/SCommonTests` from sview whole and unchanged; the extraction to the sibling `scommon` repository then replaces the copy, and `Package.swift` swaps the `SCommon` target for the dependency in one commit. Done on 2026-10-28 (Phase 6): the copy is gone and `SNotateCore` depends on scommon 0.1.0. Logged in `DECISIONS.md`.

## Alternatives considered

| Option | Verdict |
| --- | --- |
| Extend sView with an annotation mode | Two different cores (cache versus document) in one app; each would compromise the other. No, keep siblings. |
| SwiftUI `Canvas` for drawing | Fine on screen, but export would need a second renderer or `ImageRenderer`, and pixel-exact parity is the whole point. No. |
| Metal | Nothing here needs it; screenshots are static. No. |
| PencilKit or the system markup view (`QLPreviewView` markup) | Flattens, opaque format, no numbering across images. No. |
| Sidecar as Markdown or YAML | Geometry in Markdown is unreadable; YAML needs a parser. JSON via `Codable` is zero-dep and diffable. |
| One sidecar per image | More files, harder to renumber counters across steps. One per case. |
| Fork or script Shottr | No API beyond URL schemes, closed source. No. |

## Risks

- Writing back one bullet of the memo without touching the rest: the locator must handle CRLF, trailing spaces, images referenced twice; covered by tests on real memos from the poc tree.
- Deterministic PNG export depends on ImageIO being stable across macOS versions; the golden tests will tell when it is not, and the `notated/` folder is regenerable anyway.
- Core Image blur at the edge of a region bleeds; clamp the input extent before filtering.
- Mixed 1x and 2x captures in one case (seen in a real PoC tree) would make counters and blur regions land in the wrong place; the recorded step size and the exact-multiple rule handle it, and sCapture's fixed-scale capture prevents it going forward.
