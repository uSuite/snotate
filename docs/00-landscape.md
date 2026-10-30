# sNotate: landscape

sNotate is the sibling of sView: an image notation tool for the PoC evidence folders, where a case folder holds the screenshots of one procedure, step by step, and the memo beside them becomes a report or manual page. It annotates each step, keeps the sequence as a storyboard, and still saves one PNG per step. Written 2026-10-25 from the pages linked at the bottom.

## Shottr in 5 lines

1. Free (pay what you want, nag screen until activated) macOS screenshot tool, Catalina or newer, native, about 2.4 MB download; the developer's own numbers are 17 ms to grab and 165 ms to show a capture.
2. Capture modes cover area, window, any window, fullscreen, scrolling (any app), 3-second delay and "repeat last area"; the editor opens immediately after every capture, there is no overlay or history.
3. Annotation set is the one to copy: arrows (straight, curved, bendable), rectangles and ovals, text, freehand, highlighter, spotlight, numbered step counters, magnifier callout, blur and pixelate (with a text-only mode), plus developer extras (ruler, guides, colour picker, contrast checker, OCR, QR).
4. Output is clipboard, Cmd+S to a folder, drag and drop, print, S3-compatible upload; PNG or JPEG, retina saved at 144 dpi with optional downscale; measurements in logical points by default with a toggle to physical pixels; "Add Capture" composes several captures on one canvas and overlays allow before/after comparison.
5. What it does not do, and where sNotate lives: it edits one image at a time with no notion of a sequence, a shared style, a caption or a document; annotations are flattened on save, so a typo on step 7 means redoing step 7.

## Others worth a glance

- CleanShot X (paid, $35 one-off or cloud subscription): the polished all-rounder with capture history, quick-access overlay, backgrounds, recording; still one image per edit, no sequence.
- Xnapper (paid): "beautiful screenshot" focus, padding, gradients, auto-balance; presentation rather than documentation.
- Scribe, Tango, StepGrab, Guidejar (SaaS, browser or desktop recorders): the closest to the use case; record a task once, get numbered steps with cropped screenshots and auto text, export to PDF or Markdown. Cost per seat, cloud-hosted, locked formats, no control over the capture folder or the memo; the right idea with the wrong ownership model.
- Preview and the system screenshot markup: free, always there, flattens on save, no sequence, clumsy numbering.
- Skitch (Evernote, discontinued): proof that a tiny arrow-and-text tool with great defaults is enough for most documentation screenshots.
- Figma: the mental model Sam asked for (frames in a row, consistent components, one file many frames, export each frame as PNG) applied here to screenshots instead of UI mock-ups.

## What sNotate takes

| Aspect | Shottr | Scribe-style tools | sNotate |
| --- | --- | --- | --- |
| Unit of work | one capture | one recorded task | one case folder (`poc-<product>-<area>-<action>/`) |
| Annotations | flattened on save | hidden in the SaaS | plain-text sidecar beside the images, re-rendered on export |
| Numbering | per image | per task | per case, counters continue across steps |
| Captions | none | auto text | the `- description` bullets of the memo `<case-id>.md`, edited in place |
| Style | per annotation | theme | one `styles` file per machine, report palette, every image in a report looks the same |
| Output | one PNG | PDF or hosted page | one PNG per step with the original name, the memo untouched, originals kept |
| Capture | built in | built in | not here; sCapture, the third sibling, owns it |

## Sources

- [Shottr](https://shottr.cc/)
- [CleanShot vs Shottr](https://thesweetbits.com/cleanshot-vs-shottr/)
- [Scribe vs Tango (2026)](https://dubble.so/compare/scribe-vs-tango)
- [StepGrab announcement](https://forums.macrumors.com/threads/stepgrab-record-a-task-once-get-an-annotated-step-by-step-guide-menu-bar-app.2485533/)
