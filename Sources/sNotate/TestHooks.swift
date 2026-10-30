import AppKit
import QuartzCore
import SNotateCore

/// Environment switches for scripted runs (`make smoke`), in the manner of
/// sView's: no Screen Recording permission is needed, since the snapshot is
/// the canvas drawing itself into a bitmap.
@MainActor
enum TestHooks {
    static let environment = ProcessInfo.processInfo.environment

    /// `SNOTATE_WINDOW_SIZE=1200x760` opens windows at that content size.
    static let windowSize: CGSize? = {
        guard let text = environment["SNOTATE_WINDOW_SIZE"] else {
            return nil
        }
        let parts = text.split(separator: "x").compactMap { Double($0) }
        return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : nil
    }()

    /// `SNOTATE_KEYS="a drag@1000,600:770,720 v cmd-z"`: keymap keys, and
    /// drags or clicks in the current step's stored pixels (`shift-drag@`,
    /// `alt-drag@` hold modifiers, `space-drag@` holds space to pan,
    /// `view-drag@` takes view points instead, to check zoom and pan,
    /// `board-drag@` takes the storyboard's own points),
    /// `dclick@` double-clicks), and `type@text`
    /// typed into the field with focus (`_` is a space), played on the first
    /// case window; keys go to whatever has focus. `SNOTATE_SNAPSHOT=<file.png>` then saves the
    /// window's content and quits.
    /// Before launch finishes: a scripted run ignores saved window state,
    /// so the alert AppKit shows after a crash ("quit unexpectedly while
    /// reopening windows") never blocks the next run.
    /// A run driven by `SNOTATE_KEYS` or `SNOTATE_SNAPSHOT`.
    static var isScripted: Bool {
        environment["SNOTATE_KEYS"] != nil || environment["SNOTATE_SNAPSHOT"] != nil || settingsPane != nil
    }

    /// `SNOTATE_SETTINGS=general|presets` opens the Settings window on that
    /// pane after launch (SN-506); with `SNOTATE_SNAPSHOT=<file.png>` its
    /// content is saved and the app quits.
    static var settingsPane: SettingsWindowController.Pane? {
        environment["SNOTATE_SETTINGS"].flatMap(SettingsWindowController.Pane.init)
    }

    static func snapshotSettings(_ controller: SettingsWindowController?) {
        say("settings", controller?.window?.title ?? "none")
        guard let snapshot = environment["SNOTATE_SNAPSHOT"], let view = controller?.window?.contentView else {
            return
        }
        MainQueue.after(1) {
            save(view, to: URL(fileURLWithPath: snapshot))
            NSApp.terminate(nil)
        }
    }

    static func prepare() {
        guard isScripted else {
            return
        }
        UserDefaults.standard.register(defaults: ["ApplePersistenceIgnoreState": true])
        startTiming(["launch to first paint"])
    }

    static func run(on controller: CaseWindowController) {
        let keys = environment["SNOTATE_KEYS"]
        let snapshot = environment["SNOTATE_SNAPSHOT"]
        guard keys != nil || snapshot != nil else {
            return
        }
        let tokens = (keys ?? "").split(separator: " ").map(String.init)
        MainQueue.after(0.5) {
            // The step's first frame, in which AppKit converts the capture
            // for display once, timed apart from the frames tools draw.
            let start = Date()
            controller.canvas.displayIfNeeded()
            CATransaction.flush()
            report("first frame", since: start)
            play(tokens[...], on: controller, snapshot: snapshot)
        }
    }

    /// One token per main-queue block, not a loop in a task: tokens drive
    /// AppKit, which may throw (see `MainQueue`).
    private static func play(
        _ tokens: ArraySlice<String>,
        on controller: CaseWindowController,
        snapshot: String?
    ) {
        guard let token = tokens.first else {
            guard let snapshot else {
                return
            }
            MainQueue.after(0.3) {
                save(controller.window?.contentView ?? controller.canvas, to: URL(fileURLWithPath: snapshot))
                controller.close()
                NSApp.terminate(nil)
            }
            return
        }
        play(token, on: controller.canvas, board: controller.storyboardView)
        // `wait@<ms>` gives background work, such as an export, time.
        let pause = token.hasPrefix("wait@") ? Int(token.dropFirst("wait@".count)) ?? 80 : 80
        MainQueue.after(Double(pause) / 1000) {
            play(tokens.dropFirst(), on: controller, snapshot: snapshot)
        }
    }

    private static func play(
        _ token: String,
        on canvas: CanvasView,
        board: StoryboardView
    ) {
        // `drop@<file>@x,y`: a file dropped on the storyboard at its point;
        // `paste@<file>`: the file put on the hook's pasteboard, then cmd-v.
        if token.hasPrefix("drop@") {
            let parts = token.dropFirst("drop@".count).split(separator: "@")
            let xy = parts[1].split(separator: ",").compactMap { Double($0) }
            board.drop([URL(fileURLWithPath: String(parts[0]))], at: CGPoint(x: xy[0], y: xy[1]))
            return
        }
        if token.hasPrefix("paste@") {
            let pasteboard = pasteboard
            pasteboard.clearContents()
            pasteboard.writeObjects([URL(fileURLWithPath: String(token.dropFirst("paste@".count))) as NSURL])
            play("cmd-v", on: canvas, board: board)
            return
        }
        if token.hasPrefix("wait@") {
            // Handled by the loop in `run`, which sleeps between tokens.
            return
        }
        // `raise@<reason>`: an Objective-C exception, as a misbehaving
        // AppKit call would throw; AppKit catches it and the app must live
        // on, activation included (DECISIONS 2026-10-27).
        if token.hasPrefix("raise@") {
            NSException(name: .genericException, reason: String(token.dropFirst("raise@".count)), userInfo: nil).raise()
        }
        if token.hasPrefix("type@") {
            let text = token.dropFirst("type@".count).replacingOccurrences(of: "_", with: " ")
            (canvas.window?.firstResponder as? NSTextView)?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            return
        }
        if let at = token.range(of: "drag@") ?? token.range(of: "click@") {
            let double = token.hasPrefix("dclick@")
            var flags: NSEvent.ModifierFlags = []
            let prefix = token[..<at.lowerBound]
            if prefix.contains("shift-") {
                flags.insert(.shift)
            }
            if prefix.contains("alt-") {
                flags.insert(.option)
            }
            let points = token[at.upperBound...].split(separator: ":").map { pair -> CGPoint in
                let xy = pair.split(separator: ",").compactMap { Double($0) }
                return CGPoint(x: xy[0], y: xy[1])
            }
            let space = prefix.contains("space-")
            if space {
                spaceKey(.keyDown, on: canvas)
            }
            // Placed in the view when the press starts, as a hand would be,
            // even if the drag pans the image.
            let onBoard = prefix.contains("board-")
            let target: NSView = onBoard ? board : canvas
            let view = prefix.contains("view-") || onBoard ? points : points.map(canvas.viewPoint)
            mouse(from: view[0], to: view.last!, flags: flags, clicks: 1, on: target)
            if space {
                spaceKey(.keyUp, on: canvas)
            }
            if double {
                mouse(from: view[0], to: view.last!, flags: flags, clicks: 2, on: target)
            }
            return
        }
        guard let keys = try? Key.parseSequence(token), let window = canvas.window else {
            FileHandle.standardError.write(Data("bad key token \(token)\n".utf8))
            return
        }
        for key in keys {
            guard let event = KeyTranslator.event(for: key, in: window) else {
                continue
            }
            // Menu key equivalents first, as AppKit does for a real press.
            // A scripted run's window is not key, so the menu would find no
            // target; send the item's action to the first responder as a
            // key window would.
            let responder = window.firstResponder ?? canvas
            if let item = menuItem(for: event, in: NSApp.mainMenu), let action = item.action {
                // Up the responder chain, as AppKit does, so actions the
                // window controller handles are found too.
                if (responder as? NSMenuItemValidation)?.validateMenuItem(item) ?? true {
                    _ = responder.tryToPerform(action, with: item)
                }
            } else {
                responder.keyDown(with: event)
            }
        }
    }

    /// The menu item whose key equivalent `event` presses, shift read
    /// from an uppercase equivalent or the item's modifier mask.
    private static func menuItem(for event: NSEvent, in menu: NSMenu?) -> NSMenuItem? {
        guard let menu, let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return nil
        }
        // fn counts: AppKit puts fn-e (Emoji & Symbols) in a standard Edit
        // menu, and a plain e must not match it.
        let modifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control, .function]
        let flags = event.modifierFlags.intersection(modifiers)
        for item in menu.items {
            if let found = menuItem(for: event, in: item.submenu) {
                return found
            }
            guard !item.keyEquivalent.isEmpty, item.keyEquivalent.lowercased() == characters else {
                continue
            }
            var mask = item.keyEquivalentModifierMask.intersection(modifiers)
            if item.keyEquivalent != item.keyEquivalent.lowercased() {
                mask.insert(.shift)
            }
            if mask == flags {
                return item
            }
        }
        return nil
    }

    /// `SNOTATE_DEBUG=1` prints what the window says, `title <text>` and
    /// `toast <text>`, to stderr, so `make hostile` can tell a sensible
    /// message from silence.
    static func say(_ kind: String, _ text: String) {
        guard environment["SNOTATE_DEBUG"] == "1" else {
            return
        }
        FileHandle.standardError.write(Data("\(kind) \(text)\n".utf8))
    }

    /// With `SNOTATE_DEBUG=1`, each menu command with a shortcut, as
    /// `menu <title> <keys>`, so smoke can see the keymap in the menus.
    static func sayMenus(_ menu: NSMenu?) {
        guard environment["SNOTATE_DEBUG"] == "1" else {
            return
        }
        for item in menu?.items ?? [] {
            sayMenus(item.submenu)
            if item.representedObject is MenuCommand, !item.keyEquivalent.isEmpty {
                let flags = item.keyEquivalentModifierMask
                let prefix = (flags.contains(.command) ? "cmd-" : "") + (flags.contains(.option) ? "alt-" : "")
                say("menu", "\(item.title.split(separator: "\t")[0]) \(prefix)\(item.keyEquivalent)")
            }
        }
    }

    /// The clipboard, or with `SNOTATE_PASTEBOARD=<name>` a private one, so
    /// smoke never touches the user's clipboard.
    static var pasteboard: NSPasteboard {
        environment["SNOTATE_PASTEBOARD"].map { NSPasteboard(name: NSPasteboard.Name($0)) } ?? .general
    }

    /// `SNOTATE_TRASH=<folder>`: `dd` moves captures into that folder
    /// instead of the Trash, so smoke never fills the user's.
    static var trash: ((URL) throws -> URL)? {
        environment["SNOTATE_TRASH"].map { folder in
            { url in
                let target = URL(fileURLWithPath: folder).appendingPathComponent(url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: target)
                return target
            }
        }
    }

    /// `SNOTATE_CONFIRM=1` confirms a rename plan without its sheet and
    /// prints it, so smoke can apply one.
    static var confirmsSheets: Bool {
        environment["SNOTATE_CONFIRM"] != nil
    }

    /// `SNOTATE_TIMING=1` prints how long the storyboard took from being
    /// asked for to its first paint (the 500 ms target, SN-301) and to every
    /// frame on screen having its picture.
    private static var timingStarts: [String: Date] = [:]

    static func startTiming(_ labels: [String]) {
        if environment["SNOTATE_TIMING"] != nil {
            for label in labels {
                timingStarts[label] = Date()
            }
        }
    }

    static func endTiming(_ label: String) {
        guard let start = timingStarts.removeValue(forKey: label) else {
            return
        }
        report(label, since: start)
    }

    /// `timing: <label> <ms> ms`, to a tenth of a millisecond.
    static func report(_ label: String, since start: Date) {
        report(label, milliseconds: Date().timeIntervalSince(start) * 1000)
    }

    static func report(_ label: String, milliseconds: Double) {
        guard environment["SNOTATE_TIMING"] != nil else {
            return
        }
        FileHandle.standardError.write(Data("timing: \(label) \(String(format: "%.1f", milliseconds)) ms\n".utf8))
    }

    private static func spaceKey(_ type: NSEvent.EventType, on canvas: CanvasView) {
        guard let window = canvas.window,
            let event = NSEvent.keyEvent(
                with: type,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: " ",
                charactersIgnoringModifiers: " ",
                isARepeat: false,
                keyCode: 49
            )
        else {
            return
        }
        if type == .keyDown {
            canvas.keyDown(with: event)
        } else {
            canvas.keyUp(with: event)
        }
    }

    /// A press at `start`, ten moves and a release at `end`, view points.
    private static func mouse(
        from start: CGPoint,
        to end: CGPoint,
        flags: NSEvent.ModifierFlags,
        clicks: Int,
        on canvas: NSView
    ) {
        guard let window = canvas.window else {
            return
        }
        func event(_ type: NSEvent.EventType, _ t: CGFloat) -> NSEvent? {
            let point = canvas.convert(CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t), to: nil)
            return NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: clicks,
                pressure: 1
            )
        }
        event(.leftMouseDown, 0).map(canvas.mouseDown)
        // One frame per event, as a hand on a trackpad gives, so
        // SNOTATE_TIMING can time the response to each (SN-606): handling,
        // drawing, and the commit in which AppKit replays the drawing on
        // the main thread.
        for step in 1...10 {
            let start = Date()
            let cpu = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            event(.leftMouseDragged, CGFloat(step) / 10).map(canvas.mouseDragged)
            canvas.displayIfNeeded()
            CATransaction.flush()
            report("drag frame", since: start)
            // The main thread's own work in that frame, without the wait
            // for the window server, which a loaded machine stretches.
            report("drag frame cpu", milliseconds: Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - cpu) / 1_000_000)
            // Paced at 120 Hz when timed: a burst of commits with no frame
            // between them backs up the window server, which no hand does.
            if environment["SNOTATE_TIMING"] != nil {
                Thread.sleep(forTimeInterval: max(0, 1.0 / 120 - Date().timeIntervalSince(start)))
            }
        }
        event(.leftMouseUp, 1).map(canvas.mouseUp)
    }

    private static func save(_ view: NSView, to url: URL) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
